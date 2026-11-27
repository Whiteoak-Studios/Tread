--[[
    The GapCrossing check's pure parts: the floor, walls and passes laid out
    from its config, each crossing's ticks as the server saw them, the judge
    of the client's frames, and the line each crossing prints
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GapLine = require(ReplicatedStorage.Shared.Dev.GapLine)

local WRAP: number = 2 ^ 16 -- A block's relay tick is a u16, so a render tick meets the server's by its low 16 bits
local CLEAR: string = "Clear" -- Anti-ESP's reason for a pair whose last test found a ray open
local NONE: string = "-" -- A reading the crossing never gave
local SIDES: { number } = { -1, 1 } -- The walls either way of the gap along Z, the -Z one first
local ACROSS: Vector3 = Vector3.new(1, 0, 0) -- From each viewer toward the walls, the way it is set down looking
local RENDER_FIGURE: string = "%.2f" -- A render time, in relay ticks
local PLACE_FIGURE: string = "(%.2f, %.2f)" -- A rig's place across the ground
local HOLD_FIGURE: string = "%.2f s" -- The hold, in seconds
local SEPARATOR: string = ", " -- Between the parts of one line

type Capture = GapLine.Capture
type Frame = GapLine.Frame
type Place = GapLine.Place

export type Config = typeof(require(ServerScriptService.Server.Config.GapCrossing))

-- A block's place and size, centered
export type Part = {
	center: Vector3,
	size: Vector3,
}

-- One viewer spot and the path behind the walls a target sprints along from it
export type Pass = {
	name: string, -- How its lines name it, by the viewer's studs from the wall line and the path's behind it
	spot: Vector3, -- The viewer's feet on the floor's top
	look: Vector3, -- The way the viewer is set down looking, level and toward the walls
	path: number, -- The X the target sprints along
	reach: number, -- Studs either way of the gap's Z the path runs
	distance: number, -- Studs from the viewer's feet to the path
	shadow: number, -- Studs either way of the gap's Z the walls hide the path from the viewer's feet
}

export type Layout = {
	center: Vector3, -- The gap's middle on the floor's top
	floor: Part,
	walls: { Part }, -- The visible walls, the -Z one first
	occluders: { Part }, -- Each wall's occluder-only part, in the same order
	passes: { Pass },
}

-- What the server saw of the target on one relay tick, which the check refills each tick
export type Seen = {
	tick: number, -- The relay tick, as the server counts it
	zone: boolean, -- Whether the target stood within the zone either way of the gap
	hull: boolean, -- Whether the hull set's exact test found it visible
	body: boolean, -- Whether the body set's did
	reason: string, -- Anti-ESP's reason for the pair, as the relay asked
	revealed: { number }?, -- The past ages of a reveal of the target the tick's blocks carried, nil for none
	hid: boolean, -- Whether they carried a hide of it
}

-- One crossing of the path, from the server's ticks and, once its line comes, the client's frames
export type Crossing = {
	pass: string,
	kind: string, -- near or far, by anti-ESP's near radius
	index: number, -- Which of the pass's crossings, from 1
	direction: number, -- 1 for one along +Z, -1 along -Z
	open: { [number]: boolean }, -- The hull set's open ticks in the zone, by their low 16 bits
	bodyOpen: { [number]: boolean }, -- And the body set's
	bodyTicks: { number }, -- The body set's open ticks in the zone again, as the server counts them, in order
	entered: number?, -- The first tick in the zone the hull set found the target visible
	bodyEntered: number?,
	closed: number?, -- The first one in the zone after that it didn't
	bodyClosed: number?,
	last: string, -- Anti-ESP's reason on the tick before
	found: number?, -- The first tick in the zone anti-ESP's reason turned Clear
	rode: number?, -- The first tick in the zone whose blocks carried the target's reveal
	past: { number }?, -- That reveal's past ages, oldest first
	lastClear: number?, -- The last tick since found the reason was Clear, before the hide rode
	hideRode: number?, -- The first tick after closed whose blocks carried the target's hide
	lenient: number, -- G8's body-set episodes over the crossing, under each reading
	strict: number,
	client: Capture?, -- The client's frames, nil until its line came
	missing: string?, -- Why the client's part is missing, nil while it isn't
	late: number?, -- The client's frames in the body set's open ticks with the rig undrawn
	hullLate: number?, -- And in the hull set's
	unwatched: { number }?, -- The body set's open ticks the client drew no frame in, nil until its frames are judged
	drawnAt: number?, -- The first frame from the arrival on with the rig drawn
	jump: boolean?, -- Whether the frozen rig's place and its thawed place were both hidden by the walls
}

local Gap = {}

--[[
    Lays the check out from its config: the floor under every spot and
    path with its margin, two walls in line along Z either side of the gap
    with each occluder inset inside, and each pass's viewer spot out along
    -X and path behind the walls along +X, with the walls' shadow on it
--]]

function Gap.layout(config: Config): Layout
	local center: Vector3 = config.center
	local wall: index<Config, "wall"> = config.wall
	local size: Vector3 = Vector3.new(wall.width, wall.height, wall.length)
	local middle: number = config.gap / 2 + wall.length / 2 -- Each wall's middle from the gap's
	local ends: number = config.gap / 2 + wall.length -- Each wall's far end from the gap's middle

	local walls: { Part } = {}
	local occluders: { Part } = {}
	for _, side: number in SIDES do
		local at: Vector3 = center + Vector3.new(0, wall.height / 2, side * middle)
		table.insert(walls, { center = at, size = size })
		table.insert(occluders, { center = at, size = size - Vector3.one * (2 * wall.inset) })
	end

	local passes: { Pass } = {}
	local farthest: number = 0
	local deepest: number = 0
	local longest: number = 0
	for _, pass: { viewer: number, behind: number, reach: number } in config.passes do
		local distance: number = pass.viewer + pass.behind
		table.insert(passes, {
			name = `viewer {pass.viewer} path {pass.behind}`,
			spot = center - Vector3.new(pass.viewer, 0, 0),
			look = ACROSS,
			path = center.X + pass.behind,
			reach = pass.reach,
			distance = distance,
			shadow = ends * distance / pass.viewer,
		})

		farthest = math.max(farthest, pass.viewer)
		deepest = math.max(deepest, pass.behind)
		longest = math.max(longest, pass.reach)
	end

	local margin: number = config.margin
	local thickness: number = config.thickness
	local floor: Part = {
		center = center + Vector3.new((deepest - farthest) / 2, -thickness / 2, 0),
		size = Vector3.new(farthest + deepest + 2 * margin, thickness, 2 * (longest + margin)),
	}

	return { center = center, floor = floor, walls = walls, occluders = occluders, passes = passes }
end

-- A relay tick, or a render time's whole tick, by the low 16 bits a block carries
function Gap.wire(tick: number): number
	return math.floor(tick) % WRAP
end

-- A crossing before its first tick
function Gap.crossing(pass: string, kind: string, index: number, direction: number): Crossing
	return {
		pass = pass,
		kind = kind,
		index = index,
		direction = direction,
		open = {},
		bodyOpen = {},
		bodyTicks = {},
		entered = nil,
		bodyEntered = nil,
		closed = nil,
		bodyClosed = nil,
		last = "",
		found = nil,
		rode = nil,
		past = nil,
		lastClear = nil,
		hideRode = nil,
		lenient = 0,
		strict = 0,
		client = nil,
		missing = nil,
		late = nil,
		hullLate = nil,
		unwatched = nil,
		drawnAt = nil,
		jump = nil,
	}
end

--[[
    What one tick's tap frame, decoded, carried for a slot's life: the past
    ages of its reveal, nil for no reveal, and whether it carried its hide
--]]

function Gap.carried(frame: { [string]: any }, slot: number, generation: number): ({ number }?, boolean)
	local revealed: { number }? = nil
	local hid: boolean = false

	for _, block: { [string]: any } in frame.blocks do
		for _, reveal: { [string]: any } in block.reveals do
			if reveal.slot == slot and reveal.generation == generation then
				local ages: { number } = {}
				for _, entry: { [string]: any } in reveal.past do
					table.insert(ages, entry.age)
				end

				revealed = ages
			end
		end

		for _, hide: { [string]: any } in block.hides do
			if hide.slot == slot and hide.generation == generation then
				hid = true
			end
		end
	end

	return revealed, hid
end

--[[
    Counts one tick into a crossing. In the zone, each set's open ticks,
    its first open one and the first closed one after it, the tick anti-ESP
    turned Clear and the first tick a reveal rode. From found on, the last
    Clear tick, until the first hide after the ray closed rides
--]]

function Gap.track(crossing: Crossing, seen: Seen)
	local tick: number = seen.tick

	if seen.zone then
		if seen.hull then
			crossing.open[Gap.wire(tick)] = true
			crossing.entered = crossing.entered or tick
		elseif crossing.entered ~= nil and crossing.closed == nil then
			crossing.closed = tick
		end

		if seen.body then
			crossing.bodyOpen[Gap.wire(tick)] = true
			table.insert(crossing.bodyTicks, tick)
			crossing.bodyEntered = crossing.bodyEntered or tick
		elseif crossing.bodyEntered ~= nil and crossing.bodyClosed == nil then
			crossing.bodyClosed = tick
		end

		if seen.reason == CLEAR and crossing.last ~= CLEAR and crossing.found == nil then
			crossing.found = tick
		end

		local revealed: { number }? = seen.revealed
		if revealed and crossing.rode == nil then
			crossing.rode = tick
			crossing.past = revealed
		end
	end

	if crossing.found ~= nil and crossing.hideRode == nil then
		if seen.reason == CLEAR then
			crossing.lastClear = tick
		end

		if seen.hid and crossing.closed ~= nil then
			crossing.hideRode = tick
		end
	end

	crossing.last = seen.reason
end

--[[
    Judges the client's frames: the frames late, each whose render time
    fell in an open tick while the rig was undrawn, and the first frame from
    the reveal's arrival on that drew the rig, nil with no arrival or none
--]]

function Gap.judge(frames: { Frame }, arrival: number?, open: { [number]: boolean }): (number, number?)
	local late: number = 0
	for _, frame: Frame in frames do
		if not frame.drawn and open[Gap.wire(frame.render)] then
			late += 1
		end
	end

	if arrival == nil then
		return late, nil
	end

	for index: number = arrival, #frames do
		if frames[index].drawn then
			return late, index
		end
	end

	return late, nil
end

--[[
    The ticks given that the client drew no frame in, in their order, a
    frame's render time meeting a tick by the low 16 bits a block carries,
    as the judge meets them
--]]

function Gap.unwatched(frames: { Frame }, ticks: { number }): { number }
	local watched: { [number]: boolean } = {}
	for _, frame: Frame in frames do
		watched[Gap.wire(frame.render)] = true
	end

	local unwatched: { number } = {}
	for _, tick: number in ticks do
		if not watched[Gap.wire(tick)] then
			table.insert(unwatched, tick)
		end
	end

	return unwatched
end

-- Whether the frozen rig's jump stayed behind the walls: both its places known, and the server's test hides each
function Gap.behind(frozen: Place?, thawed: Place?, hidden: (place: Place) -> boolean): boolean
	if frozen == nil or thawed == nil then
		return false
	end

	return hidden(frozen) and hidden(thawed)
end

-- Numbers as a line lists them, such as a reveal's past ages or a crossing's ticks
function Gap.list(values: { number }): string
	local parts: { string } = {}
	for _, value: number in values do
		table.insert(parts, tostring(value))
	end

	return table.concat(parts, ", ")
end

local function text(value: number?): string
	if value == nil then
		return NONE
	end

	return tostring(value)
end

-- The frames' drawn and undrawn runs, each by the render times it spans
local function runs(frames: { Frame }): string
	local parts: { string } = {}
	local from: number = 1

	for index: number = 2, #frames + 1 do
		local frame: Frame? = frames[index]
		local first: Frame = frames[from]
		if frame == nil or frame.drawn ~= first.drawn then
			local state: string = first.drawn and "on" or "off"
			local span: string =
				`{string.format(RENDER_FIGURE, first.render)}-{string.format(RENDER_FIGURE, frames[index - 1].render)}`
			table.insert(parts, `{state} {span}`)
			from = index
		end
	end

	if #parts == 0 then
		return "no frames"
	end

	return table.concat(parts, " ")
end

local function placeText(place: Place?): string
	if place == nil then
		return NONE
	end

	return string.format(PLACE_FIGURE, place.x, place.z)
end

-- The client's part of a crossing's line, or why it is missing
local function clientPart(crossing: Crossing): string
	local capture: Capture? = crossing.client
	if not capture then
		return `client missing: {crossing.missing or "no line came"}`
	end

	local arrival: number? = capture.arrival
	local arrived: string = "no reveal arrived"
	if arrival ~= nil then
		local frame: Frame? = capture.frames[arrival]
		local render: string = NONE
		if frame then
			render = string.format(RENDER_FIGURE, frame.render)
		end

		arrived = `reveal arrived at render {render}, frame {arrival}`
	end

	local drawnAt: number? = crossing.drawnAt
	local drawn: string = "never drawn after it"
	if drawnAt ~= nil and arrival ~= nil then
		drawn = `drawn at frame {drawnAt} ({drawnAt - arrival} after)`
	end

	local unwatched: { number }? = crossing.unwatched
	local unseen: string = `unwatched {NONE}`
	if unwatched then
		unseen = `unwatched {#unwatched}`
		if #unwatched > 0 then
			unseen = `{unseen} (ticks {Gap.list(unwatched)})`
		end
	end

	local parts: { string } = {
		`client {#capture.frames} frames`,
		arrived,
		drawn,
		runs(capture.frames),
		`frozen at {placeText(capture.frozen)}`,
		`thawed at {placeText(capture.thawed)}`,
		`lateFrames {text(crossing.late)} (hull set {text(crossing.hullLate)})`,
		unseen,
		`jump behind the walls {crossing.jump == true}`,
	}

	if capture.cut > 0 then
		table.insert(parts, `{capture.cut} frames cut`)
	end

	return table.concat(parts, SEPARATOR)
end

--[[
    A crossing's line: when the exact rays entered the gap, when anti-ESP
    found it and how far ahead, the reveal that rode with its past, the
    client's frames and their judgment, when the rays closed and the hide
    rode, the hold from the last Clear to it, and G8's episodes

    @ rate | relay ticks a second, which the hold counts seconds by
    @ pastOn | whether the server's relay.past is on, without which no reveal carries a past
--]]

function Gap.line(crossing: Crossing, rate: number, pastOn: boolean): string
	local direction: string = crossing.direction > 0 and "+Z" or "-Z"
	local head: string = `GapCrossing {crossing.pass} ({crossing.kind}) crossing {crossing.index} along {direction}`

	local entered: number? = crossing.entered
	local found: number? = crossing.found
	local ahead: string = ""
	if entered ~= nil and found ~= nil then
		ahead = ` ({found - entered} from entered)`
	end

	local past: { number }? = crossing.past
	local carried: string = "no reveal rode"
	if crossing.rode ~= nil and past then
		carried = `rode {crossing.rode} with past {#past}`
		if #past > 0 then
			carried = `{carried} (ages {Gap.list(past)})`
		end

		if not pastOn then
			carried = `{carried} (relay.past is off)`
		end
	end

	local hold: string = NONE
	local hideRode: number? = crossing.hideRode
	local lastClear: number? = crossing.lastClear
	if hideRode ~= nil and lastClear ~= nil then
		hold = string.format(HOLD_FIGURE, (hideRode - lastClear) / rate)
	end

	local parts: { string } = {
		`entered {text(entered)} (body {text(crossing.bodyEntered)})`,
		`found {text(found)}{ahead}`,
		carried,
		clientPart(crossing),
		`closed {text(crossing.closed)} (body {text(crossing.bodyClosed)})`,
		`hide rode {text(hideRode)}, hold {hold} from the last Clear`,
		`G8 body episodes lenient {crossing.lenient} strict {crossing.strict}`,
	}

	return `{head}: {table.concat(parts, SEPARATOR)}`
end

return Gap
