--[[
    G8's late reveals: what each observed viewer holds, rebuilt from the
    relay tap, each enemy it doesn't tested at anti-ESP's body points and
    its hull's, episodes counted two ways, and the doorway and window check
--]]

--!strict
--!native
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Engine = require(Packages.Tread.Step.Engine)
local Programs = require(ServerScriptService.Server.Bots.Programs)

-- Requiring it finds the module the running server started, whose verdicts each episode names
local AntiEsp = require(Packages.Tread.Server.AntiEsp)

local VIEWERS: number = require(ServerScriptService.Server.Config.Reveals).viewers
local GROUP: string = require(ServerScriptService.Server.Config.Reveals).group
local BODY: { string } = require(ServerScriptService.Server.Config.Reveals).body
local INSET: number = require(ServerScriptService.Server.Config.Reveals).inset
local GRACE: number = require(ServerScriptService.Server.Config.Reveals).grace
local OpeningsConfig = require(ServerScriptService.Server.Config.Reveals).openings

local FOLDERS: { { string } } = OpeningsConfig.folders
local BATCH: number = OpeningsConfig.batch
local SETTLE: number = OpeningsConfig.settle
local HOLD: number = OpeningsConfig.hold
local PROBE: number = OpeningsConfig.probe
local VIEW: number = OpeningsConfig.view
local MARGIN: number = OpeningsConfig.margin
local INSIDE: number = OpeningsConfig.inside
local PLATFORM: Vector3 = OpeningsConfig.platform
local LIFT: number = OpeningsConfig.lift
local VERSION: number = Tread.CODEC_VERSION
local SLOT_IDS: number = 4096 -- A character's id is its slot plus its generation times this, as the record packs it
local SECONDS_PER_HOUR: number = 3600
local MILLISECONDS: number = 1000
local P95: number = 0.95
local WORST: number = 1 -- The share of the reads at or under the worst
local LEVEL: number = 1e-6 -- Below this a marker's axis flattened onto the ground has no direction
local SEED: number = 1 -- An idle bot draws nothing, so its seed never matters
local FOLDER: string = "Openings" -- The folder the check lays its platforms in
local OPENINGS_GROUP: string = "openings" -- What the fleet's entries call the check's bots
local SEPARATOR: string = "; " -- Between the parts of one line
local CENTER: number = 1 -- The hull's center, the first of its points
local BODY_SET: string = "body" -- The points anti-ESP aims at, which G8's line counts
local HULL_SET: string = "hull" -- The hull's center and corners
local HULL_ONLY: string = "hull only" -- The summary's group of hull reveals that began with no body point open
local GROUPS: { string } = { BODY_SET, HULL_SET, HULL_ONLY } -- In the order the summary prints them
local READINGS: { string } = { "lenient", "strict" } -- Each reading, in the order the summary prints them
local LEVELS: { number } = { 1, -1 } -- The corners' shares up the hull, the top four first, as the summary groups them

-- The hull's center, then its eight corners, as shares of its half size along its own axes, its -Z the way it faces
-- and its +X its right
local POINTS: { Vector3 } = {
	Vector3.zero,
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

type Key = Player | Volt.Bot

-- What a viewer holds: each slot it is currently sent, with the generation of the life it is sent
export type Held = { [number]: number }

-- True when a ray from origin along direction, its whole length, meets an occluder, as Engine.occlusion's test is
export type Blocked = (origin: vector, direction: vector) -> boolean

-- How far a cast from origin along direction, its whole length, gets before it meets the world
export type Free = (origin: Vector3, direction: Vector3) -> number

-- The fields of the step's state AntiEsp.aimPoints reads, which the harness fills from a public state
export type Aimed = {
	position: vector, -- The feet
	velocity: vector,
	posture: Tread.Posture,
	mode: Tread.Mode,
}

-- One episode of a target visible to a viewer that isn't sent it, under one set of points
export type Episode = {
	set: string, -- body or hull
	reading: string, -- lenient or strict
	viewer: string,
	target: string,
	real: boolean, -- Whether the viewer is a real player
	distance: number, -- Studs from the viewer's eye to the target's hull center at its start
	point: number, -- The index in its set of the point whose ray opened at its start
	height: number, -- That point's height over the target's feet, in studs
	speed: number, -- The target's speed across the ground at its start, in studs a second
	start: number, -- The relay tick it began on
	length: number, -- Relay ticks it lasted
	reason: string, -- Anti-ESP's reason for the pair at its start
	hullOnly: boolean, -- A hull episode that began with no body point open
}

-- One tick's look at a pair under one set, which the harness refills for each
export type Sighting = {
	set: string, -- body or hull, which a refill never changes
	tick: number,
	sent: boolean,
	visible: boolean, -- Read only while unsent
	distance: number, -- Read only while visible and unsent, as is each field after it
	point: number, -- The index in its set of the first point whose ray was open
	height: number, -- That point's height over the target's feet, in studs
	speed: number, -- The target's speed across the ground, in studs a second
	reason: string,
	hullOnly: boolean, -- A hull sighting with no body point open on its tick
}

-- What one viewer and one target's life keep from tick to tick
export type Pair = {
	unsentSince: number?, -- The tick its unsent stretch began, nil while sent
	opening: Sighting?, -- A copy of its run of visible and unsent ticks' first sighting, nil outside one
	lenient: Episode?, -- The lenient episode its run counted, nil before the run passes the grace
	strict: Episode?, -- The strict episode under way
}

-- What the bot harness's runs call around their window
export type Probe = {
	start: (entries: { any }) -> (), -- After the warm-up's stats read, with the fleet's entries
	stop: (samples: { [string]: { number } }) -> string, -- After the window, with every figure it read
}

-- The sizes a placement stands its two bodies by
export type Sizes = {
	probe: number,
	view: number,
	margin: number,
	inside: number,
	radius: number,
	standing: number, -- The standing hull's height
	eye: number, -- The standing eye's height over the feet
}

-- Where one opening's pair stands: the axis through it toward the viewer, and each body's feet
export type Placement = {
	normal: Vector3,
	target: Vector3,
	viewer: Vector3,
}

-- One observed viewer of the G8 load
type Watch = {
	key: Key,
	name: string,
	real: boolean,
	character: () -> Tread.Character?, -- Read each tick, since a real player's may change
	held: Held,
	bodies: { [number]: Pair }, -- The body set's, by the target's id
	hulls: { [number]: Pair }, -- The hull set's
	stop: () -> (),
}

-- One opening's pair in the doorway and window check
type Opening = {
	marker: BasePart,
	placement: Placement,
	target: Tread.Character?,
	viewer: Tread.Character?,
	key: Key?,
	held: Held,
	stop: (() -> ())?,
	seen: boolean, -- Whether the body set ever found its target visible
	failed: boolean, -- Whether it ever did while the viewer wasn't sent it
	hullFailed: boolean, -- Whether the hull set ever did
	failOpens: number, -- Ticks the pair was sent by failing open
}

-- One test's aim ends, and the fields of its target's step state that AntiEsp.aimPoints reads, refilled by each test
local Ends: { vector } = {}
local AimTarget: Aimed = { position = vector.zero, velocity = vector.zero, posture = "Stand", mode = "Ground" }

local Reveals = {}

--[[
    Seeds what a viewer holds from its keyframe, decoded: every character
    it is currently sent, those marked withheld from a spectate's target
    left out
--]]

function Reveals.seed(held: Held, keyframe: { [string]: any })
	table.clear(held)

	for _, character: { [string]: any } in keyframe.characters do
		if not character.withheld then
			held[character.record.slot] = character.record.generation
		end
	end
end

--[[
    What one relay tick's tap frame, decoded, changes in what a viewer
    holds: a reveal starts a slot's life's stretch, and a hide of that life
    ends it, a repeated pending one changing nothing
--]]

function Reveals.apply(held: Held, frame: { [string]: any })
	for _, block: { [string]: any } in frame.blocks do
		for _, hide: { [string]: any } in block.hides do
			if held[hide.slot] == hide.generation then
				held[hide.slot] = nil
			end
		end

		for _, reveal: { [string]: any } in block.reveals do
			held[reveal.slot] = reveal.generation
		end
	end
end

--[[
    The hull set's test: rays from the eye to the hull's center and then its
    eight corners, each pulled inset studs inside, and whether one was open,
    with the rays cast, the test stopping at the first open one, so a
    visible hull's count is its open point's index in POINTS
--]]

function Reveals.visible(eye: Vector3, box: Tread.Box, blocked: Blocked, inset: number): (boolean, number)
	local half: Vector3 = box.size / 2 - Vector3.one * inset
	local origin: vector = Engine.toVector(eye)

	for index: number, share: Vector3 in POINTS do
		local point: Vector3 = box.cframe * (half * share)
		if not blocked(origin, Engine.toVector(point - eye)) then
			return true, index
		end
	end

	return false, #POINTS
end

--[[
    The body set's test: rays from the eye to the first count aim ends, and
    whether one was open, with the rays cast, the test stopping at the first
    open one, so a visible body's count is its open point's index
--]]

function Reveals.bodyVisible(eye: vector, ends: { vector }, count: number, blocked: Blocked): (boolean, number)
	for index: number = 1, count do
		if not blocked(eye, ends[index] - eye) then
			return true, index
		end
	end

	return false, count
end

-- Fills in place the fields of the step's state AntiEsp.aimPoints reads from a public state
function Reveals.adapt(into: Aimed, state: Tread.State)
	into.position = Engine.toVector(state.root)
	into.velocity = Engine.toVector(state.velocity)
	into.posture = state.posture
	into.mode = state.mode
end

--[[
    Tests an unsent target from a viewer's eye on both sets and refills each
    set's sighting with what it found: the body set at the points anti-ESP
    aims at for the pair with no look-ahead, and the hull set at its
    standing box, a hull sighting hull only while no body point is open
--]]

function Reveals.sight(body: Sighting, hull: Sighting, eye: Vector3, target: Tread.State, blocked: Blocked)
	local from: vector = Engine.toVector(eye)
	Reveals.adapt(AimTarget, target)

	-- A cast, since the step's state has fields aimPoints never reads
	local count: number = AntiEsp.aimPoints(from, AimTarget :: any, Ends)
	local bodyOpen: boolean, bodyPoint: number = Reveals.bodyVisible(from, Ends, count, blocked)

	local box: Tread.Box = target.standingBox
	local hullOpen: boolean, hullPoint: number = Reveals.visible(eye, box, blocked, INSET)
	local half: number = box.size.Y / 2 -- The box stands on the feet, its center half its height up

	local velocity: Vector3 = target.velocity
	local distance: number = (target.hullCenter - eye).Magnitude
	local speed: number = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	body.visible = bodyOpen
	body.distance = distance
	body.point = bodyPoint
	body.height = Ends[bodyPoint].y - AimTarget.position.y
	body.speed = speed

	hull.visible = hullOpen
	hull.distance = distance
	hull.point = hullPoint
	hull.height = half + (half - INSET) * POINTS[hullPoint].Y
	hull.speed = speed
	hull.hullOnly = not bodyOpen
end

-- A pair before its first tick
function Reveals.pair(): Pair
	return {
		unsentSince = nil,
		opening = nil,
		lenient = nil,
		strict = nil,
	}
end

-- A set's sighting before its first tick, which the harness refills for every pair
function Reveals.sighting(set: string): Sighting
	return {
		set = set,
		tick = 0,
		sent = false,
		visible = false,
		distance = 0,
		point = 0,
		height = 0,
		speed = 0,
		reason = "",
		hullOnly = false,
	}
end

-- An episode found under a reading, starting at the sighting given
local function begin(
	found: { Episode },
	reading: string,
	viewer: string,
	target: string,
	real: boolean,
	from: Sighting
): Episode
	local episode: Episode = {
		set = from.set,
		reading = reading,
		viewer = viewer,
		target = target,
		real = real,
		distance = from.distance,
		point = from.point,
		height = from.height,
		speed = from.speed,
		start = from.tick,
		length = 1,
		reason = from.reason,
		hullOnly = from.hullOnly,
	}

	table.insert(found, episode)

	return episode
end

--[[
    Counts one tick of a pair into the episodes found, each maximal stretch
    once under each reading. Lenient: visible and unsent for more than the
    grace in a row. Strict: visible at a tick its unsent stretch began more
    than the grace before. A sent tick ends both, and an unseen one each run

    @ grace | relay intervals
--]]

function Reveals.track(
	pair: Pair,
	seen: Sighting,
	grace: number,
	found: { Episode },
	viewer: string,
	target: string,
	real: boolean
)
	local tick: number = seen.tick
	if seen.sent then
		pair.unsentSince = nil
		pair.opening = nil
		pair.lenient = nil
		pair.strict = nil

		return
	end

	local unsentSince: number = pair.unsentSince or tick
	pair.unsentSince = unsentSince

	if not seen.visible then
		pair.opening = nil
		pair.lenient = nil
		pair.strict = nil

		return
	end

	-- A copy, since the harness refills one sighting for every pair
	local opening: Sighting = pair.opening or table.clone(seen)
	pair.opening = opening

	local run: number = tick - opening.tick + 1
	local lenient: Episode? = pair.lenient
	if lenient then
		lenient.length = run
	elseif run > grace then
		local opened: Episode = begin(found, "lenient", viewer, target, real, opening)
		opened.length = run
		pair.lenient = opened
	end

	local strict: Episode? = pair.strict
	if tick - unsentSince <= grace then
		pair.strict = nil
	elseif strict then
		strict.length += 1
	else
		pair.strict = begin(found, "strict", viewer, target, real, seen)
	end
end

-- A marker's axis flattened onto the ground, as a unit vector
local function level(axis: Vector3): Vector3
	local flat: Vector3 = Vector3.new(axis.X, 0, axis.Z)
	if flat.Magnitude < LEVEL then
		error("A marker turned off level gives no horizontal axis to find its opening's along")
	end

	return flat.Unit
end

--[[
    Where an opening's pair stands. Its axis is the marker's horizontal
    axis whose shorter side, cast probe studs both ways, is the longer, and
    the viewer's side the roomier along it. The target's hull is centered at
    the marker's height just inside, and the viewer's eye at it, out to view
--]]

function Reveals.place(marker: CFrame, free: Free, sizes: Sizes): Placement
	local center: Vector3 = marker.Position
	local axis: Vector3 = Vector3.zero
	local widest: number = -math.huge

	for _, candidate: Vector3 in { level(marker.RightVector), level(marker.LookVector) } do
		local shorter: number = math.min(free(center, candidate * sizes.probe), free(center, -candidate * sizes.probe))
		if shorter > widest then
			axis = candidate
			widest = shorter
		end
	end

	local reach: number = sizes.view + sizes.radius + sizes.margin
	local normal: Vector3 = axis
	local room: number = free(center, axis * reach)
	local back: number = free(center, -axis * reach)
	if back > room then
		normal = -axis
		room = back
	end

	local out: number = math.min(sizes.view, room - sizes.radius - sizes.margin)

	return {
		normal = normal,
		target = center - normal * (sizes.radius + sizes.inside) - Vector3.new(0, sizes.standing / 2, 0),
		viewer = center + normal * out - Vector3.new(0, sizes.eye, 0),
	}
end

-- A character's slot and generation, which its handle keeps private
local function lifeOf(character: Tread.Character): (number, number)
	local inner: any = character
	return inner._slot, inner._generation
end

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

local function sum(samples: { number }): number
	local total: number = 0
	for _, value: number in samples do
		total += value
	end

	return total
end

--[[
    A point's plain name in its set: a body point by its configured name,
    and of the hull the center, or a corner by its height, then front or
    back along the facing, then its side
--]]

local function nameOf(set: string, index: number): string
	if set == BODY_SET then
		return BODY[index]
	elseif index == CENTER then
		return "center"
	end

	local share: Vector3 = POINTS[index]
	local height: string = share.Y > 0 and "top" or "bottom"
	local depth: string = share.Z < 0 and "front" or "back"
	local side: string = share.X < 0 and "left" or "right"

	return `{height} {depth} {side}`
end

--[[
    An episode's line, as each prints, naming its set and the point that
    opened it, for a hull episode whether a body point was open as it began,
    and ending with the target's speed across the ground
--]]

function Reveals.describe(episode: Episode): string
	local who: string = `{episode.viewer} saw {episode.target}`
	local measure: string = string.format("%.1f studs away for %d relay ticks", episode.distance, episode.length)
	local since: string = `from tick {episode.start}, anti-ESP's reason {episode.reason}`
	local name: string = nameOf(episode.set, episode.point)
	local opened: string = string.format("opened at point %d (%s, %.2f studs up)", episode.point, name, episode.height)
	local speed: string = string.format("horizontal speed %.1f studs/s", episode.speed)

	if episode.set == HULL_SET then
		local body: string = episode.hullOnly and HULL_ONLY or "a body point open too"
		opened = `{opened}, {body}`
	end

	return `G8 {episode.set} {episode.reading} late reveal: {who} {measure} {since}, {opened}, {speed}`
end

--[[
    One line of a window's late reveals by the point whose ray opened each,
    each set by its own points under each reading: the body set's by name,
    then the hull's center, its four top corners and its four bottom
    corners, each corner group with its total
--]]

function Reveals.byPoint(episodes: { Episode }): string
	local tallies: { [string]: { [string]: { number } } } = { [BODY_SET] = {}, [HULL_SET] = {} }
	for _, reading: string in READINGS do
		tallies[BODY_SET][reading] = table.create(#BODY, 0)
		tallies[HULL_SET][reading] = table.create(#POINTS, 0)
	end

	for _, episode: Episode in episodes do
		local tally: { number } = tallies[episode.set][episode.reading]
		tally[episode.point] += 1
	end

	local lines: { string } = {}
	for _, reading: string in READINGS do
		local tally: { number } = tallies[BODY_SET][reading]
		local points: { string } = {}

		for index: number, name: string in BODY do
			table.insert(points, `{name} {tally[index]}`)
		end

		table.insert(lines, `{BODY_SET} {reading} {table.concat(points, ", ")}`)
	end

	for _, reading: string in READINGS do
		local tally: { number } = tallies[HULL_SET][reading]
		local groups: { string } = { `{HULL_SET} {reading} center {tally[CENTER]}` }

		for _, up: number in LEVELS do
			local total: number = 0
			local corners: { string } = {}

			for index: number, share: Vector3 in POINTS do
				if share.Y == up then
					total += tally[index]
					table.insert(corners, `{nameOf(HULL_SET, index)} {tally[index]}`)
				end
			end

			local group: string = up > 0 and "top" or "bottom"
			table.insert(groups, `{group} corners {total} ({table.concat(corners, ", ")})`)
		end

		table.insert(lines, table.concat(groups, ", "))
	end

	return `G8 late reveals by the point that opened them: {table.concat(lines, SEPARATOR)}`
end

-- Late reveals a viewer-hour, a dash with no time watched
local function rate(count: number, hours: number): string
	if hours <= 0 then
		return "-"
	end

	return string.format("%.2f", count / hours)
end

-- Every group's count under each reading, each at zero
local function zeroCounts(): { [string]: { [string]: number } }
	local counts: { [string]: { [string]: number } } = {}
	for _, group: string in GROUPS do
		counts[group] = { lenient = 0, strict = 0 }
	end

	return counts
end

-- Counts an episode under its set, and under the hull-only group too when it is one
local function countInto(counts: { [string]: { [string]: number } }, episode: Episode)
	counts[episode.set][episode.reading] += 1

	if episode.hullOnly then
		counts[HULL_ONLY][episode.reading] += 1
	end
end

--[[
    The summary line's counts, each group's under each reading: the body
    set's first, which G8's line reads, then the hull set's and the
    hull-only reveals', each for every viewer, real players alone and every
    seed so far

    @ hours | the window's viewer-hours, realHours its real players' and pooledHours every seed's so far
--]]

function Reveals.counts(
	found: { Episode },
	pooled: { Episode },
	hours: number,
	realHours: number,
	pooledHours: number
): string
	local window: { [string]: { [string]: number } } = zeroCounts()
	local real: { [string]: { [string]: number } } = zeroCounts()
	local seeds: { [string]: { [string]: number } } = zeroCounts()

	for _, episode: Episode in found do
		countInto(window, episode)

		if episode.real then
			countInto(real, episode)
		end
	end

	for _, episode: Episode in pooled do
		countInto(seeds, episode)
	end

	local parts: { string } = {}
	for _, group: string in GROUPS do
		local all: { [string]: number } = window[group]
		local players: { [string]: number } = real[group]
		local every: { [string]: number } = seeds[group]

		local lenient: string = `lenient {all.lenient} ({rate(all.lenient, hours)} a viewer-hour)`
		local strict: string = `strict {all.strict} ({rate(all.strict, hours)} a viewer-hour)`
		local realLenient: string = `lenient {players.lenient} ({rate(players.lenient, realHours)})`
		local realStrict: string = `strict {players.strict} ({rate(players.strict, realHours)})`
		local pooledLenient: string = `lenient {rate(every.lenient, pooledHours)}`
		local pooledStrict: string = `strict {rate(every.strict, pooledHours)}`

		table.insert(parts, `{group} {lenient}, {strict}`)
		table.insert(parts, `real players alone {group} {realLenient}, {realStrict} a viewer-hour`)
		table.insert(parts, `every seed so far {group} {pooledLenient}, {pooledStrict} a viewer-hour`)
	end

	return table.concat(parts, SEPARATOR)
end

--[[
    The G8 load's probe: from its start every real player with a character
    and the first bots of the configured group are observed, each tick's
    unsent enemies within relevancy tested on both sets, and its stop
    prints every episode and a line of them by the point that opened each,
    and gives each set's rates, anti-ESP's frame cost and the harness's
    own. Totals pool across the seeds it is started for
--]]

function Reveals.probe(): Probe
	-- Required here, so this module's pure parts load without the dev game, as its cases load them
	local Game: any = require(ServerScriptService.Server.Game)

	local server: Tread.Server, _: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local blocked: Blocked = Engine.occlusion(settings.antiEsp.include)
	local enter: number = settings.relevancy.enter

	local watches: { Watch } = {}
	local found: { Episode } = {}
	local bodySeen: Sighting = Reveals.sighting(BODY_SET)
	local hullSeen: Sighting = Reveals.sighting(HULL_SET)
	local began: number = 0
	local cost: number = 0 -- Seconds the sinks took
	local ticks: number = 0 -- Relay ticks they ran on
	local lastTick: number? = nil
	local targets: { Tread.Target } = {} -- Every target, read once a relay tick by its first sink

	-- Pooled across the seeds
	local pooledFound: { Episode } = {}
	local pooledHours: number = 0

	-- One viewer's tick: each enemy player within relevancy it isn't sent, tested on both sets from its cleared eye
	local function look(watch: Watch, tick: number)
		local viewer: Tread.Character? = watch.character()
		if not viewer then
			return
		end

		local read: boolean, state: any = pcall(viewer.getState, viewer)
		if not read then
			return
		end

		local eye: Vector3 = state.eye
		local root: Vector3 = state.root

		for _, target: Tread.Target in targets do
			-- NPCs are always sent and sleepers are G9's; only a character has a player
			local owner: any = (target :: any).player
			if target == viewer or owner == nil then
				continue
			end

			local character: Tread.Character = target :: Tread.Character
			local slot: number, generation: number = lifeOf(character)
			local id: number = slot + generation * SLOT_IDS
			local targetState: Tread.State = character:getState()

			if (targetState.root - root).Magnitude > enter then
				watch.bodies[id] = nil
				watch.hulls[id] = nil
				continue
			end

			local body: Pair = watch.bodies[id] or Reveals.pair()
			local hull: Pair = watch.hulls[id] or Reveals.pair()
			watch.bodies[id] = body
			watch.hulls[id] = hull

			local sent: boolean = watch.held[slot] == generation
			bodySeen.tick = tick
			bodySeen.sent = sent
			bodySeen.visible = false
			hullSeen.tick = tick
			hullSeen.sent = sent
			hullSeen.visible = false

			if not sent then
				Reveals.sight(bodySeen, hullSeen, eye, targetState, blocked)

				if bodySeen.visible or hullSeen.visible then
					local reason: string = AntiEsp.reason(watch.key, slot)
					bodySeen.reason = reason
					hullSeen.reason = reason
				end
			end

			Reveals.track(body, bodySeen, GRACE, found, watch.name, owner.Name, watch.real)
			Reveals.track(hull, hullSeen, GRACE, found, watch.name, owner.Name, watch.real)
		end
	end

	local function watch(key: Key, name: string, real: boolean, character: () -> Tread.Character?)
		local entry: Watch = {
			key = key,
			name = name,
			real = real,
			character = character,
			held = {},
			bodies = {},
			hulls = {},
			stop = function () end,
		}

		Reveals.seed(entry.held, Tread.decode(VERSION, "keyframe", server:keyframe(key)))

		-- Disconnected at stop, or by the taps when the viewer leaves
		entry.stop = server:observe(key, function (tick: number, data: buffer)
			local started: number = os.clock()
			if tick ~= lastTick then
				lastTick = tick
				ticks += 1
				targets = server:getAll()
			end

			Reveals.apply(entry.held, Tread.decode(VERSION, "tap", data))
			look(entry, tick)
			cost += os.clock() - started
		end)

		table.insert(watches, entry)
	end

	local function start(entries: { any })
		table.clear(watches)
		table.clear(found)
		cost = 0
		ticks = 0
		lastTick = nil
		began = os.clock()

		for _, player: Player in Players:GetPlayers() do
			if Game.characterOf(player) then
				watch(player, player.Name, true, function (): Tread.Character?
					return Game.characterOf(player)
				end)
			end
		end

		local taken: number = 0
		for _, entry: any in entries do
			if taken >= VIEWERS then
				break
			elseif entry.group == GROUP then
				taken += 1

				local character: Tread.Character = entry.character
				watch(entry.volt, entry.volt.Name, false, function (): Tread.Character?
					return character
				end)
			end
		end
	end

	local function stop(samples: { [string]: { number } }): string
		for _, entry: Watch in watches do
			entry.stop()
		end

		local seconds: number = os.clock() - began
		local real: number = 0
		for _, entry: Watch in watches do
			if entry.real then
				real += 1
			end
		end

		local viewerHours: number = #watches * seconds / SECONDS_PER_HOUR
		local realHours: number = real * seconds / SECONDS_PER_HOUR
		pooledHours += viewerHours

		for _, episode: Episode in found do
			print(Reveals.describe(episode))
			table.insert(pooledFound, episode)
		end

		print(Reveals.byPoint(found))

		local p95s: { number } = samples.antiEspP95Ms or {}
		local worst: number = percentile(p95s, WORST)
		local frameCost: string =
			string.format("antiEsp p95 reads p95 %.3f ms, worst %.3f ms", percentile(p95s, P95), worst)
		local failOpens: string = `{sum(samples.antiEspFailOpens or {})} fail-opens`
		local harness: string =
			string.format("harness %.3f ms a relay tick", ticks > 0 and cost * MILLISECONDS / ticks or 0)

		local watched: string =
			string.format("%d viewers (%d real) over %.2f viewer-hours", #watches, real, viewerHours)

		local parts: { string } = {
			watched,
			Reveals.counts(found, pooledFound, viewerHours, realHours, pooledHours),
			frameCost,
			failOpens,
			harness,
		}

		return `G8: {table.concat(parts, SEPARATOR)}`
	end

	return { start = start, stop = stop }
end

-- Every marker part under the configured folders, by full name, and the folders that are missing
local function markers(): ({ BasePart }, { string })
	local found: { BasePart } = {}
	local missing: { string } = {}

	for _, path: { string } in FOLDERS do
		local current: Instance? = Workspace
		for _, name: string in path do
			current = current and current:FindFirstChild(name)
		end

		if not current then
			table.insert(missing, `Workspace.{table.concat(path, ".")}`)
			continue
		end

		for _, descendant: Instance in current:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(found, descendant)
			end
		end
	end

	table.sort(found, function (a: BasePart, b: BasePart): boolean
		return a:GetFullName() < b:GetFullName()
	end)

	return found, missing
end

-- A platform a bot stands on, its top at the feet given
local function platform(feet: Vector3, parent: Instance)
	local part: Part = Instance.new("Part")
	part.Name = "Platform"
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Size = PLATFORM
	part.CFrame = CFrame.new(feet - Vector3.new(0, PLATFORM.Y / 2, 0))
	part.Parent = parent
end

--[[
    The doorway and window check: a target bot just inside each marker and
    a viewer bot out along its opening's axis, both idle on laid platforms,
    in batches, each viewer's sink connected as it is built. A marker fails
    when the body set finds its target visible at a tick of the batch's
    hold while its viewer isn't sent it, those only the hull set would fail
    count beside, and one the body set never sees is unplaced. It passes
    when it ran cleanly and judges no gate
--]]

function Reveals.openings(limit: number?): (boolean, string)
	-- Required here, so this module's pure parts load without the dev game, as its cases load them
	local Fleet: any = require(ServerScriptService.Server.Bots.Fleet)
	local Game: any = require(ServerScriptService.Server.Game)

	local server: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return false, "Workspace.TestContent is missing, so the dev game's casts take no platform laid"
	end

	local all: { BasePart }, missing: { string } = markers()
	if #missing > 0 then
		return false, `the marker folders {table.concat(missing, ", ")} are missing`
	end

	local count: number = #all
	if limit then
		count = math.min(limit, count)
	end

	local include: { Instance }? = shared.collision.include
	if not include then
		return false, "the dev game's collision names no parts for the openings' casts to meet"
	end

	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = true

	local function free(origin: Vector3, direction: Vector3): number
		local hit: RaycastResult? = Workspace:Raycast(origin, direction, params)
		if hit then
			return hit.Distance
		end

		return direction.Magnitude
	end

	local sizes: Sizes = {
		probe = PROBE,
		view = VIEW,
		margin = MARGIN,
		inside = INSIDE,
		radius = shared.step.radius,
		standing = shared.step.standing,
		eye = shared.step.eyeStanding,
	}

	-- Every pair placed before any platform is laid, so no platform meets another opening's casts
	local openings: { Opening } = {}
	for index: number = 1, count do
		local marker: BasePart = all[index]
		table.insert(openings, {
			marker = marker,
			placement = Reveals.place(marker.CFrame, free, sizes),
			target = nil,
			viewer = nil,
			key = nil,
			held = {},
			stop = nil,
			seen = false,
			failed = false,
			hullFailed = false,
			failOpens = 0,
		})
	end

	local blocked: Blocked = Engine.occlusion(settings.antiEsp.include)
	local folder: Folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = testContent

	local holding: boolean = false
	local problems: { string } = {}
	local bodySeen: Sighting = Reveals.sighting(BODY_SET)
	local hullSeen: Sighting = Reveals.sighting(HULL_SET)

	-- One relay tick of an opening's viewer: its hold set, and while the batch holds, its target tested on both sets
	local function sink(opening: Opening, data: buffer)
		Reveals.apply(opening.held, Tread.decode(VERSION, "tap", data))

		local target: Tread.Character? = opening.target
		local viewer: Tread.Character? = opening.viewer
		local key: Key? = opening.key
		if not holding or not target or not viewer or key == nil then
			return
		end

		local slot: number, generation: number = lifeOf(target)
		local unsent: boolean = opening.held[slot] ~= generation
		Reveals.sight(bodySeen, hullSeen, viewer:getState().eye, target:getState(), blocked)

		if bodySeen.visible then
			opening.seen = true
			opening.failed = opening.failed or unsent
		end

		opening.hullFailed = opening.hullFailed or (hullSeen.visible and unsent)

		if AntiEsp.reason(key, slot) == "FailOpen" then
			opening.failOpens += 1
		end
	end

	local function build(opening: Opening, index: number)
		local placement: Placement = opening.placement
		platform(placement.target, folder)
		platform(placement.viewer, folder)

		local lift: Vector3 = Vector3.new(0, LIFT, 0)
		local target: any = Fleet.add({
			name = `Opening{index}Target`,
			group = OPENINGS_GROUP,
			at = CFrame.new(placement.target + lift),
			steer = Programs.idle(),
			faults = nil,
			seed = SEED,
		})

		local viewer: any = Fleet.add({
			name = `Opening{index}Viewer`,
			group = OPENINGS_GROUP,
			at = CFrame.new(placement.viewer + lift),
			steer = Programs.idle(),
			faults = nil,
			seed = SEED,
		})

		opening.target = target.character
		opening.viewer = viewer.character
		opening.key = viewer.volt

		-- Straight after the viewer is built, so its sink hears its first reveal; disconnected after the batch
		Reveals.seed(opening.held, Tread.decode(VERSION, "keyframe", server:keyframe(viewer.volt)))
		opening.stop = server:observe(viewer.volt, function (_: number, data: buffer)
			sink(opening, data)
		end)
	end

	local ran: boolean, failure: any = pcall(function ()
		for first: number = 1, #openings, BATCH do
			local last: number = math.min(first + BATCH - 1, #openings)
			for index: number = first, last do
				build(openings[index], index)
			end

			task.wait(SETTLE)
			holding = true
			task.wait(HOLD)
			holding = false

			for index: number = first, last do
				local stop: (() -> ())? = openings[index].stop
				if stop then
					stop()
				end
			end

			for _, problem: string in Fleet.clear() do
				table.insert(problems, problem)
			end

			folder:ClearAllChildren()
		end
	end)

	-- Everything it made goes, whatever the batches did
	holding = false
	for _, opening: Opening in openings do
		local stop: (() -> ())? = opening.stop
		if stop then
			stop()
		end
	end

	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	folder:Destroy()

	if not ran then
		table.insert(problems, `it threw: {failure}`)
	end

	local failed: { string } = {}
	local unplaced: { string } = {}
	local hullOnly: number = 0 -- Markers only the hull set would have failed
	local failOpens: number = 0
	for _, opening: Opening in openings do
		failOpens += opening.failOpens

		if opening.failed then
			table.insert(failed, opening.marker:GetFullName())
		elseif not opening.seen then
			table.insert(unplaced, opening.marker:GetFullName())
		end

		if opening.hullFailed and not opening.failed then
			hullOnly += 1
		end
	end

	local parts: { string } = {
		`{#openings} of {#all} markers`,
		`{#failed} failed {table.concat(failed, ", ")}`,
		`{hullOnly} only the hull set would have failed`,
		`{#unplaced} unplaced {table.concat(unplaced, ", ")}`,
		`{failOpens} fail-open ticks`,
	}

	for _, problem: string in problems do
		table.insert(parts, problem)
	end

	local line: string = `Openings: {table.concat(parts, SEPARATOR)}`
	print(line)

	return #problems == 0, line
end

return Reveals
