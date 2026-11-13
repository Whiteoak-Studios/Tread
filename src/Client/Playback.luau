--[[
    A moderator's clip played on the client: its keyframe and tap frames read
    once, then each render drawn from the clip time alone, every character
    from the client's own pool as the target saw it, the eye the target's
--]]

--!strict
--!native
local Playback = {}
Playback.__index = Playback

local Block = require(script.Parent.Parent.Codec.Block)
local ClientPlatforms = require(script.Parent.Platforms)
local Constants = require(script.Parent.Parent.Constants)
local Eye = require(script.Parent.Parent.Step.Eye)
local Feed = require(script.Parent.Parent.Codec.Feed)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Interpolate = require(script.Parent.Interpolate)
local Keyframe = require(script.Parent.Parent.Codec.Keyframe)
local Math = require(script.Parent.Parent.Step.Math)
local OwnerState = require(script.Parent.Parent.Codec.OwnerState)
local Platforms = require(script.Parent.Parent.Step.Platforms)
local Public = require(script.Parent.Parent.Step.Public)
local Record = require(script.Parent.Parent.Codec.Record)
local Rigs = require(script.Parent.Rigs)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.Parent.Codec.StateWord)
local Tap = require(script.Parent.Parent.Codec.Tap)
local Types = require(script.Parent.Parent.Types)
local World = require(script.Parent.Parent.Step.World)

local WRAP: number = 2 ^ 16 -- The values a u16 tick holds
local YAW_STEPS: number = Constants.ANGLE_STEPS / (2 * math.pi) -- Steps a radian of facing, the units Sequence wraps
local RECORD_BYTES: number = Constants.RECORD_BYTES
local TAP_BLOCK_BYTES: number = Constants.TAP_BLOCK_BYTES -- A tap frame's block, which may pass a relay block's 896 B
local TICK_BYTES: number = 8 -- Each sample's relay tick, an f64, as the interpolation's ring keeps it
local WINDOW: number = 8 -- The newest samples a life is drawn from, as the interpolation's ring keeps them
local WITHHELD_INTERVALS: number = 4 -- Relay intervals a withheld character goes unrefreshed before it is dropped
local GENERATIONS: number = 2 ^ Constants.GENERATION_BITS -- A generation wraps inside the record's bits beside the slot
local HALF_GENERATIONS: number = GENERATIONS / 2
local MILLISECONDS: number = 1000 -- A second's, which a frame's view lag counts in
local SEEK: number = 1 -- Seconds a render may move on from the last and still be play, past which it is a seek
local AUTHORED: number = 1 -- The track speed a clip's end gives back, each track's own
local UNSEEN: number = math.huge -- A distance past any draw distance, which puts a rig out of Workspace until it shows

type Collision = State.Collision
type Footstep = Block.Footstep
type Kind = Block.Kind
type Layout = Fields.Layout
type Look = Feed.Look
type Platform = State.Platform
type Slot = Types.Slot
type StepState = State.State
type Values = State.Values
type World = State.World

-- The lean and head cone a record's last byte and a frame's looks step to
type Limits = { lean: number, headCone: number }

-- The shared table's rates, in Hz
export type Rates = { simulation: number, relay: number }

-- What the client handle hands a playback, and the signals it raises for it
export type Settings = {
	rigs: Rigs.Rigs, -- The client's own pool, which no live rig holds while a playback runs
	world: World, -- The client's world, whose settings, water and rules the clip's own world shares
	collision: Collision, -- The step's casts with no platform in them, which the clip's world wraps with its own
	platforms: { Platform }, -- Every platform registered on the client, which the clip's world registers again
	clock: number?, -- The server's simulation tick as the client counts it, nil before the handshake names it
	layout: Layout, -- The game's declarations, compiled
	limits: Limits,
	rates: Rates,
	eye: vector, -- Where the eye was last drawn, which it stays at until the clip draws one
	look: vector,
	spawned: (slot: Slot, rig: Model) -> (),
	despawned: (slot: Slot) -> (),
	heard: (step: Footstep) -> (),
	ended: () -> (), -- The handle's own end of the playback, which draws the live characters again
}

-- One tap frame as read, at its relay tick unwrapped from the keyframe's
type Parsed = {
	tick: number,
	frame: Tap.Frame,
	index: number, -- Its place in the list it came in, which a refusal names
}

-- One OwnerState of the target's, as the frame at its relay tick carried it
type Owner = {
	tick: number, -- The frame's relay tick, unwrapped from the keyframe's
	simulation: number, -- The simulation tick its command ran on, counted on from the first OwnerState's
	lag: number, -- Relay ticks the target's view of the others ran behind it
	id: number, -- The target's character, its slot plus its generation times 4,096
	state: StepState,
}

-- A command the target stepped, by the simulation tick it ran on, and its look
type Stepped = {
	tick: number,
	look: Look,
}

-- What a slot shows from a clip tick on: its stretch open or not, with its life, kind and whether it is withheld
type Mark = {
	at: number,
	after: boolean, -- True when it holds only past at, false from at on
	open: boolean,
	generation: number,
	kind: Kind,
	withheld: boolean,
	first: number, -- Its stretch's first sample
	falls: number, -- The first fall of the place its sleeper lies in
}

-- A moved sleeper's fall, from the clip tick its record arrived
type Fall = {
	at: number,
	from: vector,
	fromYaw: number,
	to: vector,
	toYaw: number,
}

-- A look or held part of one life, from the clip tick its block arrived; a held part's values are nil for none
type Part = {
	at: number,
	generation: number,
	values: Values?,
}

-- One slot as the clip has it, built once: what it shows over the clip, its samples, falls and parts
type Track = {
	slot: number,
	marks: { Mark },
	ticks: { number }, -- Each sample's relay tick, the tick its block arrived, oldest first
	records: { buffer }, -- Each sample's record, until they are packed below
	sampleTicks: buffer, -- The ticks and records packed as the interpolation's sample reads them
	sampleRecords: buffer,
	falls: { Fall },
	looks: { Part },
	lookTicks: { number },
	helds: { Part },
	heldTicks: { number },

	-- The live rules' state for the slot as the clip's blocks are read, in the order they arrived
	life: number?, -- Its generation
	kind: Kind?, -- The open stretch's kind, nil while none is open
	changed: number?, -- The tick of the newest reveal or hide this life applied
	hide: number?, -- A waiting hide's tick
	closing: number, -- The clip tick that hide closes the stretch at, once the render time reaches it
	withheldAt: number?, -- The newest withheld record's tick, while the stretch is withheld
	first: number,
	fallFirst: number,
	place: vector?, -- Where a sleeper's newest record lies, nil before one in this place
	placeYaw: number,
	gravity: number, -- The keyframe's, which its sleepers' falls are drawn under
}

-- A slot with a clip rig out of the pool, and what the rig was last given
type Drawn = {
	slot: Slot,
	generation: number,
	look: Part?,
	held: Part?,
	shown: boolean, -- Whether its last pose drew it
	outlined: boolean,
	state: StepState, -- What each render draws it from
	seen: number, -- The render that last kept it out
}

type Fields = {
	_settings: Settings,
	_rigs: Rigs.Rigs,
	_world: World, -- The clip's own world: the platforms called at the keyframe's presses, which the eye meets
	_limits: Limits,
	_rate: number, -- rates.relay
	_share: number, -- Simulation ticks a relay tick
	_start: number, -- The keyframe's relay tick, which every clip tick counts on from
	_gravity: number, -- The keyframe's, studs/s², which the clip's sleepers fall under
	_length: number, -- Seconds from the keyframe to the last frame
	_offset: number, -- The server's simulation tick less the clip's own count of it
	_owners: { Owner },
	_ownerTicks: { number },
	_frameTicks: { number }, -- Each observed frame's relay tick
	_owned: { boolean }, -- Whether each carries an OwnerState
	_commands: { Look }, -- The looks of the target's stepped commands, oldest first
	_commandTicks: { number },
	_steps: { Footstep }, -- The footsteps, oldest first
	_stepTicks: { number },
	_tracks: { Track },
	_tracked: { [number]: Track }, -- By slot
	_drawn: { [number]: Drawn }, -- Each slot with a clip rig out, by slot
	_watched: number?, -- The slot the pool was last told is the target's
	_target: StepState, -- The target as the last render drew it
	_eye: vector,
	_look: vector,
	_time: number?, -- The last render's time, nil before the first
	_framed: number?, -- The time the last frame saw
	_seeked: boolean, -- Whether a render since the last frame was a seek
	_speed: number, -- The track speed the pool was last given
	_renders: number,
	_ended: boolean,
}

-- What the reads reuse, so building a clip makes a table only for what it keeps
local Read: Block.Block = Block.new()
local Moved: Record.Record = Record.new()
local Lying: Record.Record = Record.new()

-- Runs where one of the game's rig hooks raised an error, so its warning keeps the hook's stack
local function warnHook(message: unknown)
	local stack: string = debug.traceback(tostring(message), 2)
	warn(`A rig hook threw for a clip's rig, and the playback carried on without it: {stack}`)
end

-- The last index of an ascending list whose value is at or before a value, 0 for none
local function latest(values: { number }, value: number): number
	local low: number = 1
	local high: number = #values
	local found: number = 0

	while low <= high do
		local middle: number = (low + high) // 2

		if values[middle] <= value then
			found = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	return found
end

-- The mark a slot shows at a clip tick, the last one that holds by then, nil before its first
local function markAt(marks: { Mark }, clip: number): Mark?
	local low: number = 1
	local high: number = #marks
	local found: Mark? = nil

	while low <= high do
		local middle: number = (low + high) // 2
		local mark: Mark = marks[middle]

		if clip > mark.at or (clip == mark.at and not mark.after) then
			found = mark
			low = middle + 1
		else
			high = middle - 1
		end
	end

	return found
end

-- A life's newest part at a clip tick, nil when the newest one by then is an older life's or there is none
local function partAt(parts: { Part }, ticks: { number }, generation: number, clip: number): Part?
	local part: Part? = parts[latest(ticks, clip)]
	if part == nil or part.generation ~= generation then
		return nil
	end

	return part
end

--[[
    Reads a list of tap frames from its first given index, each tick
    unwrapped from the one before, erroring naming the frame that isn't one,
    comes before the keyframe's tick or no later than the frame before, and
    for withheld frames one that carries an OwnerState
--]]

local function parse(
	list: { buffer },
	from: number,
	start: number,
	limits: Limits,
	what: string,
	withheld: boolean
): { Parsed }
	local parsed: { Parsed } = {}
	local previous: number? = nil

	for index: number = from, #list do
		local data: any = list[index]
		if typeof(data) ~= "buffer" then
			error(`client:play's {what} {index} is a {typeof(data)}, not a buffer`, 0)
		end

		local read: boolean, result: any = pcall(Tap.read, data, limits)
		if not read then
			error(`client:play's {what} {index} isn't a tap frame: {result}`, 0)
		end

		local frame: Tap.Frame = result
		local reference: number = previous or start
		local tick: number = reference + Sequence.difference(frame.tick, reference % WRAP)

		if tick < start then
			error(`client:play's {what} {index} comes before the keyframe's relay tick`, 0)
		elseif previous ~= nil and tick <= previous then
			error(`client:play's {what} {index} is out of order, no later than the one before it`, 0)
		elseif withheld and frame.owner ~= nil then
			error(`client:play's {what} {index} carries an OwnerState, which no withheld frame does`, 0)
		end

		previous = tick
		table.insert(parsed, { tick = tick, frame = frame, index = index })
	end

	return parsed
end

-- The signed difference a - b of two generations, the shorter way round their wrap
local function generationsAhead(a: number, b: number): number
	return (a - b + HALF_GENERATIONS) % GENERATIONS - HALF_GENERATIONS
end

-- Notes what a slot shows from a clip tick on, as its rules now hold it, the last note at that tick standing
local function mark(track: Track, at: number, after: boolean)
	local marks: { Mark } = track.marks
	local last: Mark? = marks[#marks]
	local note: Mark = {
		at = at,
		after = after,
		open = track.kind ~= nil,
		generation = track.life or 0,
		kind = track.kind or "Player",
		withheld = track.withheldAt ~= nil,
		first = track.first,
		falls = track.fallFirst,
	}

	if last and last.at == at and last.after == after then
		marks[#marks] = note
	else
		table.insert(marks, note)
	end
end

-- Forgets where a sleeper lay, so its next record lies where it puts it with no fall from before
local function forget(track: Track)
	track.place = nil
	track.fallFirst = #track.falls + 1
end

-- Ends a slot's stretch, its waiting hide, its withholding and its place
local function close(track: Track)
	track.kind = nil
	track.hide = nil
	track.withheldAt = nil
	forget(track)
end

--[[
    Closes a slot's stretch whose end came before a clip tick: a waiting
    hide once the render time reached its tick, or a withheld stretch no
    withheld record refreshed for 4 relay intervals, whichever came first
--]]

local function settle(track: Track, tick: number)
	if track.kind == nil then
		return
	end

	local at: number? = nil
	local after: boolean = false
	if track.hide ~= nil and track.closing <= tick then
		at = track.closing
	end

	local last: number? = track.withheldAt
	if last ~= nil and tick > last + WITHHELD_INTERVALS then
		local drop: number = last + WITHHELD_INTERVALS

		if at == nil or drop < at then
			at = drop
			after = true
		end
	end

	if at ~= nil then
		close(track)
		mark(track, at, after)
	end
end

--[[
    Whether an entry naming a slot's generation applies to its life: the
    first names it, an older one is dropped, and a newer one ends the life
    drawn now and starts its own, with no reveal or hide of its own
--]]

local function alive(track: Track, generation: number, tick: number): boolean
	local life: number? = track.life
	if life == nil then
		track.life = generation
		return true
	end

	local ahead: number = generationsAhead(generation, life)
	if ahead < 0 then
		return false
	elseif ahead > 0 then
		local open: boolean = track.kind ~= nil
		close(track)
		track.life = generation
		track.changed = nil

		if open then
			mark(track, tick, false)
		end
	end

	return true
end

-- Applies a reveal as the live rules do, opening a stretch, changing its kind or ending its withholding
local function reveal(track: Track, kind: Kind, tick: number)
	local last: number? = track.changed
	if last ~= nil and tick <= last then
		return
	end

	track.changed = tick
	track.hide = nil

	local withheld: boolean = track.withheldAt ~= nil
	track.withheldAt = nil

	local open: Kind? = track.kind
	if open == kind then
		if withheld then
			mark(track, tick, false)
		end

		return
	elseif open == nil then
		track.first = #track.ticks + 1
	end

	track.kind = kind
	forget(track)
	mark(track, tick, false)
end

--[[
    Takes a sleeper's record lying at another place or yaw than the one
    before as a move, which falls from where an earlier fall puts it by
    then, or from where it lay, as the live rules draw it
--]]

local function move(track: Track, tick: number, record: buffer, limits: Limits)
	Record.read(record, 0, Moved, limits)

	local place: vector? = track.place
	local yaw: number = Moved.yaw
	if place == nil then
		track.place = Moved.position
		track.placeYaw = yaw

		return
	elseif place == Moved.position and track.placeYaw == yaw then
		return
	end

	local from: vector = place
	local fromYaw: number = track.placeYaw
	local falls: { Fall } = track.falls
	if #falls >= track.fallFirst then
		local fall: Fall = falls[#falls]
		from, fromYaw = Interpolate.fall(fall.from, fall.fromYaw, fall.to, fall.toYaw, fall.at, tick, track.gravity)
	end

	table.insert(falls, { at = tick, from = from, fromYaw = fromYaw, to = Moved.position, toYaw = yaw })
	track.place = Moved.position
	track.placeYaw = yaw
end

-- Adds a record to an open stretch as its newest sample, dropping one no newer than its newest or past a waiting hide
local function push(track: Track, tick: number, data: buffer, offset: number, limits: Limits)
	if track.kind == nil then
		return
	end

	local hide: number? = track.hide
	local ticks: { number } = track.ticks
	local count: number = #ticks
	if hide ~= nil and tick > hide then
		return
	elseif count >= track.first and tick <= ticks[count] then
		return
	end

	local record: buffer = buffer.create(RECORD_BYTES)
	buffer.copy(record, 0, data, offset, RECORD_BYTES)
	table.insert(ticks, tick)
	table.insert(track.records, record)

	if track.kind == "Sleeper" then
		move(track, tick, record, limits)
	end
end

--[[
    Draws a record a withheld block carries as the live rules do: it opens
    a stretch for a slot not drawn, takes back a waiting hide, and keeps
    the slot withheld until a reveal or until its records stop
--]]

local function withhold(track: Track, tick: number, data: buffer, offset: number, limits: Limits)
	local last: number? = track.changed
	if last ~= nil and tick < last then
		return
	end

	track.changed = tick
	track.hide = nil

	local newest: number? = track.withheldAt
	if newest == nil or tick > newest then
		track.withheldAt = tick
	end

	local opened: boolean = track.kind == nil
	if opened then
		track.kind = "Player"
		track.first = #track.ticks + 1
		forget(track)
	end

	if opened or newest == nil then
		mark(track, tick, false)
	end

	push(track, tick, data, offset, limits)
end

--[[
    Keeps a look or held part of a life from the clip tick its block
    arrived, unpacked once against the declarations, a held part of 0 B
    holding nothing, and errors on one its declarations refuse
--]]

local function part(
	parts: { Part },
	ticks: { number },
	list: Fields.List,
	generation: number,
	tick: number,
	data: buffer,
	at: number,
	length: number,
	held: boolean
)
	local values: Values? = nil
	if length > 0 then
		local into: Values = {}
		local failed: number? = Fields.read(list, data, at, length, into)
		if failed then
			error(`client:play's clip carries a look entry its declarations refuse at field {failed}`, 0)
		end

		values = into
	elseif not held then
		values = {}
	end

	table.insert(parts, { at = tick, generation = generation, values = values })
	table.insert(ticks, tick)
end

--[[
    Draws a sleeper's or a body's state lying at a render time, as the live
    rules do: at the sample at or before it, or along the newest fall that
    arrived by the clip tick, which holds where it lay until its own tick
--]]

local function lie(
	track: Track,
	note: Mark,
	base: number,
	newest: number,
	at: number,
	clip: number,
	limits: Limits,
	into: StepState
): boolean
	local ticks: { number } = track.ticks
	local index: number = newest
	while index >= base and ticks[index] > at do
		index -= 1
	end

	local falls: { Fall } = track.falls
	local fall: Fall? = nil
	for candidate: number = #falls, note.falls, -1 do
		if falls[candidate].at <= clip then
			fall = falls[candidate]
			break
		end
	end

	if index < base and fall == nil then
		return false
	end

	Record.read(track.sampleRecords, (math.max(index, base) - 1) * RECORD_BYTES, Lying, limits)
	StateWord.unpack(Lying.word, into)
	into.platform = Lying.platform

	if fall then
		into.position, into.facing =
			Interpolate.fall(fall.from, fall.fromYaw, fall.to, fall.toYaw, fall.at, at, track.gravity)
	else
		into.position = Lying.position
		into.facing = Lying.yaw
	end

	Interpolate.lying(into)

	return true
end

--[[
    Reads a clip once, its keyframe first and then its observed frames, with
    the withheld frames over the same ticks when given, and builds what
    each render draws from. It errors, the client unchanged, on a first
    buffer that isn't a keyframe of this CODEC_VERSION, declarations that
    hash other than the client's, a frame that isn't one, comes before the
    keyframe or out of order, and a withheld frame with an OwnerState or a
    reveal, hide or footstep entry

    @ settings | the client handle's pool, world and signals for the clip
--]]

function Playback.new(settings: Settings, ticks: { buffer }, withheld: { buffer }?): Self
	if type(ticks) ~= "table" or typeof(ticks[1]) ~= "buffer" then
		error("client:play takes the clip's ticks as a list of buffers, its keyframe first", 0)
	elseif withheld ~= nil and type(withheld) ~= "table" then
		error(`client:play takes the withheld frames as a list of buffers or nil, not a {typeof(withheld)}`, 0)
	end

	local read: boolean, result: any = pcall(Keyframe.read, ticks[1])
	if not read then
		error(`client:play's first buffer isn't a keyframe this client reads: {result}`, 0)
	end

	local keyframe: Keyframe.Keyframe = result
	local layout: Layout = settings.layout
	local hash: number = Fields.hash(layout)
	if keyframe.hash ~= hash then
		local recorded: string = `client:play's clip was recorded with declarations hashing to {keyframe.hash}`
		error(`{recorded}, not this client's {hash}`, 0)
	end

	local limits: Limits = settings.limits
	local rates: Rates = settings.rates
	local share: number = rates.simulation / rates.relay
	local start: number = keyframe.tick
	local observed: { Parsed } = parse(ticks, 2, start, limits, "frame", false)
	local hidden: { Parsed } = parse(withheld or {}, 1, start, limits, "withheld frame", true)

	-- 1) The target's OwnerStates, each simulation tick counted on from the first's, which the relay ran after
	local owners: { Owner } = {}
	local ownerTicks: { number } = {}
	local frameTicks: { number } = {}
	local owned: { boolean } = {}
	local byTick: { [number]: Look } = {}

	for _, entry: Parsed in observed do
		table.insert(frameTicks, entry.tick)
		table.insert(owned, entry.frame.owner ~= nil)

		local owner: Tap.Owner? = entry.frame.owner
		if owner then
			local state: StepState = State.new()
			local took: boolean, problem: any =
				pcall(OwnerState.read, owner.data, 0, buffer.len(owner.data), state, layout, limits)
			if not took then
				error(`client:play's frame {entry.index} carries an OwnerState that doesn't read: {problem}`, 0)
			end

			local previous: Owner? = owners[#owners]
			local simulation: number = math.ceil(entry.tick * share)
			if previous then
				simulation = previous.simulation + Sequence.difference(state.tick, previous.state.tick)
			end

			table.insert(owners, {
				tick = entry.tick,
				simulation = simulation,
				lag = owner.lag / MILLISECONDS * rates.relay,
				id = owner.id,
				state = state,
			})
			table.insert(ownerTicks, entry.tick)

			-- The newest look ran on the OwnerState's own tick, and each older one a tick before the last
			for index: number, look: Look in owner.looks do
				byTick[simulation - (index - 1)] = look
			end
		end
	end

	local stepped: { Stepped } = {}
	for tick: number, look: Look in byTick do
		table.insert(stepped, { tick = tick, look = look })
	end
	table.sort(stepped, function (a: Stepped, b: Stepped): boolean
		return a.tick < b.tick
	end)

	local commands: { Look } = {}
	local commandTicks: { number } = {}
	for _, command: Stepped in stepped do
		table.insert(commands, command.look)
		table.insert(commandTicks, command.tick)
	end

	-- 2) The clip's own world, its platforms called at the keyframe's presses
	local live: World = settings.world
	local world: World = World.new(live.settings, rates.simulation, settings.collision, live.water, live.rules, false)
	for _, platform: Platform in settings.platforms do
		Platforms.add(world, platform)
	end

	-- Whiteoak TODO: a platform called during the clip's window is drawn from the keyframe's presses before it; the
	-- upgrade is the frame carrying the calls sent on its tick, which the clip's world then applies as play passes it
	local reference: number? = nil
	for _, press: Keyframe.Platform in keyframe.platforms do
		if world.platforms[press.id] ~= nil then
			Platforms.call(world, press.id, press.tick)
		end

		if reference == nil or press.tick > reference then
			reference = press.tick
		end
	end

	-- The server's count of the clip's simulation ticks: unwrapped at or after the newest press, else the client's clock
	local first: Owner? = owners[1]
	local counted: number = math.floor(start * share)
	local low: number = counted % WRAP
	if first then
		counted = first.simulation
		low = first.state.tick
	end

	local server: number = counted
	local clock: number? = settings.clock
	if reference ~= nil then
		server = reference + (low - reference) % WRAP
	elseif clock ~= nil then
		server = clock + Sequence.difference(low, clock % WRAP)
	end

	local last: number = start
	local finalFrame: Parsed? = observed[#observed]
	local finalWithheld: Parsed? = hidden[#hidden]
	if finalFrame then
		last = finalFrame.tick
	end
	if finalWithheld and finalWithheld.tick > last then
		last = finalWithheld.tick
	end

	-- Whiteoak TODO: a gravity change during the clip's window draws the falls after it under the keyframe's gravity;
	-- the upgrade is the frame carrying the changes sent on its tick, as for the platforms' calls
	local self: Self = setmetatable({
		_settings = settings,
		_rigs = settings.rigs,
		_world = world,
		_limits = limits,
		_rate = rates.relay,
		_share = share,
		_start = start,
		_gravity = keyframe.gravity,
		_length = (last - start) / rates.relay,
		_offset = server - counted,
		_owners = owners,
		_ownerTicks = ownerTicks,
		_frameTicks = frameTicks,
		_owned = owned,
		_commands = commands,
		_commandTicks = commandTicks,
		_steps = {} :: { Footstep },
		_stepTicks = {} :: { number },
		_tracks = {} :: { Track },
		_tracked = {} :: { [number]: Track },
		_drawn = {} :: { [number]: Drawn },
		_watched = nil :: number?,
		_target = State.new(),
		_eye = settings.eye,
		_look = settings.look,
		_time = nil :: number?,
		_framed = nil :: number?,
		_seeked = false,
		_speed = AUTHORED,
		_renders = 0,
		_ended = false,
	}, Playback)

	-- 3) Every slot's stretches, samples, falls and parts, the live rules run over the blocks in the order they came
	self:_key(keyframe)

	local observing: number = 1
	local withholding: number = 1
	while observing <= #observed or withholding <= #hidden do
		local seen: Parsed? = observed[observing]
		local beside: Parsed? = hidden[withholding]

		-- At one tick the observed frame comes first, as the relay block goes before the withheld one it rides beside
		if seen and (beside == nil or seen.tick <= beside.tick) then
			for _, block: Tap.Part in seen.frame.blocks do
				self:_relay(block.data, seen.tick, seen.index)
			end

			observing += 1
		elseif beside then
			for _, block: Tap.Part in beside.frame.blocks do
				self:_withheld(block.data, beside.tick, beside.index)
			end

			withholding += 1
		end
	end

	for _, track: Track in self._tracks do
		settle(track, math.huge)
		self:_pack(track)
	end

	return self
end

-- A slot's track, made the first time the clip names the slot
function Playback._track(self: Self, slot: number): Track
	local track: Track? = self._tracked[slot]
	if track then
		return track
	end

	local made: Track = {
		slot = slot,
		marks = {},
		ticks = {},
		records = {},
		sampleTicks = buffer.create(0),
		sampleRecords = buffer.create(0),
		falls = {},
		looks = {},
		lookTicks = {},
		helds = {},
		heldTicks = {},
		life = nil,
		kind = nil,
		changed = nil,
		hide = nil,
		closing = math.huge,
		withheldAt = nil,
		first = 1,
		fallFirst = 1,
		place = nil,
		placeYaw = 0,
		gravity = self._gravity,
	}

	self._tracked[slot] = made
	table.insert(self._tracks, made)

	return made
end

-- A slot's track for an entry naming its generation at a clip tick, settled up to it, or nil for an older life's
function Playback._enter(self: Self, slot: number, generation: number, tick: number): Track?
	local track: Track = self:_track(slot)
	settle(track, tick)

	if not alive(track, generation, tick) then
		return nil
	end

	return track
end

--[[
    Opens every character the keyframe holds at its tick, withheld ones
    marked, each with its newest record as its first sample and its look
    and held item, and keeps the view's own character's look and held item
--]]

function Playback._key(self: Self, keyframe: Keyframe.Keyframe)
	local start: number = keyframe.tick

	for _, character: Keyframe.Character in keyframe.characters do
		local slot: number, generation: number = Record.split(buffer.readu16(character.record, 0))
		local track: Track? = self:_enter(slot, generation, start)

		if track then
			track.kind = character.kind
			track.changed = start
			track.hide = nil
			track.first = #track.ticks + 1
			forget(track)

			if character.withheld then
				track.withheldAt = start
			end

			mark(track, start, false)
			push(track, start, character.record, 0, self._limits)
			self:_wear(track, generation, start, character.look, character.held)
		end
	end

	local own: Keyframe.Own? = keyframe.own
	if own then
		local slot: number, generation: number = Record.split(own.id)
		local track: Track? = self:_enter(slot, generation, start)

		if track then
			self:_wear(track, generation, start, own.look, own.held)
		end
	end
end

-- Keeps a keyframe character's look and held item as parts of its life, each one set for it
function Playback._wear(self: Self, track: Track, generation: number, tick: number, look: buffer, held: buffer)
	local layout: Layout = self._settings.layout

	if buffer.len(look) > 0 then
		part(track.looks, track.lookTicks, layout.slot, generation, tick, look, 0, buffer.len(look), false)
	end

	if buffer.len(held) > 0 then
		part(track.helds, track.heldTicks, layout.held, generation, tick, held, 0, buffer.len(held), true)
	end
end

-- Keeps the parts of a block's look entries, each for the life it names
function Playback._looks(self: Self, tick: number)
	local layout: Layout = self._settings.layout

	for index: number = 1, Read.lookCount do
		local look: Block.Look = Read.looks[index]
		local track: Track? = self:_enter(look.slot, look.generation, tick)

		if track then
			local generation: number = look.generation

			if look.look then
				local data: buffer, at: number, length: number = look.lookData, look.lookAt, look.lookLength
				part(track.looks, track.lookTicks, layout.slot, generation, tick, data, at, length, false)
			end

			if look.held then
				local data: buffer, at: number, length: number = look.heldData, look.heldAt, look.heldLength
				part(track.helds, track.heldTicks, layout.held, generation, tick, data, at, length, true)
			end
		end
	end
end

--[[
    Runs one of the target's relay blocks through the live rules at the
    clip tick it arrived: its hides, looks, reveals, records and footstep
    entries in that order, as the interpolation applies them. It errors on
    a change record, which a tap block carries as its whole record
--]]

function Playback._relay(self: Self, data: buffer, tick: number, frame: number)
	Block.read(data, Read, TAP_BLOCK_BYTES)
	if Read.changeCount ~= 0 then
		error(`client:play's frame {frame} carries change records, which a tap block carries whole`, 0)
	end

	for index: number = 1, Read.hideCount do
		local hide: Block.Hide = Read.hides[index]
		local track: Track? = self:_enter(hide.slot, hide.generation, tick)

		if track then
			self:_hide(track, tick)
		end
	end

	self:_looks(tick)

	for index: number = 1, Read.revealCount do
		local entry: Block.Reveal = Read.reveals[index]
		local track: Track? = self:_enter(entry.slot, entry.generation, tick)

		if track then
			reveal(track, entry.kind, tick)
		end
	end

	local records: buffer = Read.recordData
	for index: number = 1, Read.recordCount do
		local offset: number = Read.records[index]
		local slot: number, generation: number = Record.split(buffer.readu16(records, offset))
		local track: Track? = self:_enter(slot, generation, tick)

		if track then
			push(track, tick, records, offset, self._limits)
		end
	end

	for index: number = 1, Read.footstepCount do
		local step: Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
		Block.readFootstep(Read.footstepData, Read.footsteps[index], step)

		table.insert(self._steps, step)
		table.insert(self._stepTicks, tick)
	end
end

--[[
    Runs one withheld block through the live rules at the clip tick it
    arrived: its looks, then each record a stretch that stays withheld while
    its records keep coming. It errors on one with a reveal, hide, footstep
    entry or change record, which no withheld block carries
--]]

function Playback._withheld(self: Self, data: buffer, tick: number, index: number)
	Block.read(data, Read, TAP_BLOCK_BYTES)
	if Read.revealCount ~= 0 or Read.hideCount ~= 0 or Read.footstepCount ~= 0 then
		local carried: string = `client:play's withheld frame {index} carries reveal, hide or footstep entries`
		error(`{carried}, which no withheld block does`, 0)
	elseif Read.changeCount ~= 0 then
		error(`client:play's withheld frame {index} carries change records, which no withheld block does`, 0)
	end

	self:_looks(tick)

	local records: buffer = Read.recordData
	for entry: number = 1, Read.recordCount do
		local offset: number = Read.records[entry]
		local slot: number, generation: number = Record.split(buffer.readu16(records, offset))
		local track: Track? = self:_enter(slot, generation, tick)

		if track then
			withhold(track, tick, records, offset, self._limits)
		end
	end
end

--[[
    Applies a hide as the live rules do: a newer one than the life's last
    reveal or hide waits, and closes the stretch at the first clip tick
    whose render time reaches the hide's tick
--]]

function Playback._hide(self: Self, track: Track, tick: number)
	local last: number? = track.changed
	if last ~= nil and tick <= last then
		return
	end

	track.changed = tick

	if track.kind == nil or track.hide ~= nil then
		return
	end

	track.hide = tick
	track.closing = self:_reach(tick)
end

-- Packs a track's samples into the buffers the interpolation's sample reads, once every block has been read
function Playback._pack(_: Self, track: Track)
	local count: number = #track.ticks
	local ticks: buffer = buffer.create(count * TICK_BYTES)
	local records: buffer = buffer.create(count * RECORD_BYTES)

	for index: number = 1, count do
		buffer.writef64(ticks, (index - 1) * TICK_BYTES, track.ticks[index])
		buffer.copy(records, (index - 1) * RECORD_BYTES, track.records[index])
	end

	track.sampleTicks = ticks
	track.sampleRecords = records
	track.records = {}
end

--[[
    The target's drawn simulation tick at a clip tick, in the clip's own
    count, and its view lag in relay ticks: between the two OwnerStates
    around it, and on at the simulation rate before the first and past the
    last, the clip tick's own count with no OwnerState at all
--]]

function Playback._timing(self: Self, clip: number): (number, number)
	local owners: { Owner } = self._owners
	local count: number = #owners
	local share: number = self._share
	if count == 0 then
		return clip * share, 0
	end

	local index: number = latest(self._ownerTicks, clip)
	if index == 0 then
		local first: Owner = owners[1]
		return first.simulation - (first.tick - clip) * share, first.lag
	elseif index == count then
		local last: Owner = owners[count]
		return last.simulation + (clip - last.tick) * share, last.lag
	end

	local older: Owner = owners[index]
	local newer: Owner = owners[index + 1]
	local t: number = (clip - older.tick) / (newer.tick - older.tick)

	return Math.lerp(older.simulation, newer.simulation, t), Math.lerp(older.lag, newer.lag, t)
end

--[[
    The render time every other character is drawn at for a clip tick, in
    relay ticks: the target's drawn tick in relay time less its view lag,
    the time the server's hit judgment rewinds that command's shots to
--]]

function Playback._at(self: Self, clip: number): number
	local drawn: number, lag: number = self:_timing(clip)

	return drawn / self._share - lag
end

--[[
    The first clip tick at or after a hide's tick whose render time reaches
    it, which closes the stretch the hide waits on. The render time runs
    straight between each two OwnerStates and at the clip's own rate past
    the last, so it is found on the first stretch of it that reaches the tick
--]]

function Playback._reach(self: Self, tick: number): number
	local low: number = tick
	local reached: number = self:_at(low)
	if reached >= tick then
		return low
	end

	local ownerTicks: { number } = self._ownerTicks
	for index: number = latest(ownerTicks, low) + 1, #ownerTicks do
		local high: number = ownerTicks[index]
		local at: number = self:_at(high)

		if at >= tick then
			return low + (tick - reached) * (high - low) / (at - reached)
		end

		low = high
		reached = at
	end

	return low + (tick - reached)
end

--[[
    Draws a state between two OwnerStates over the share t of the time
    between them: their position, velocity, facing on the shortest arc,
    lean and eased eye height, never across a teleport or a change of
    platform, where the older holds until the newer's time. Gives the share
    it drew at, 1 at the newer from t of 1 on and 0 holding the older

    @ t | the share of the time from older to newer, 0 or more
--]]

function Playback.between(older: StepState, newer: StepState, t: number, into: StepState): number
	if t >= 1 then
		State.copy(newer, into)
		return 1
	end

	State.copy(older, into)
	if older.epoch ~= newer.epoch or older.platform ~= newer.platform then
		return 0
	end

	local from: vector = older.position
	local to: vector = newer.position
	local moving: vector = older.velocity
	local moved: vector = newer.velocity
	local fromYaw: number = older.facing * YAW_STEPS
	local toYaw: number = fromYaw + Sequence.difference(newer.facing * YAW_STEPS, fromYaw)

	into.position = vector.create(Math.lerp(from.x, to.x, t), Math.lerp(from.y, to.y, t), Math.lerp(from.z, to.z, t))
	into.velocity =
		vector.create(Math.lerp(moving.x, moved.x, t), Math.lerp(moving.y, moved.y, t), Math.lerp(moving.z, moved.z, t))
	into.facing = (Math.lerp(fromYaw, toYaw, t) % Constants.ANGLE_STEPS) / YAW_STEPS
	into.lean = Math.lerp(older.lean, newer.lean, t)
	into.eyeHeight = Math.lerp(older.eyeHeight, newer.eyeHeight, t)

	return t
end

--[[
    Moves a remote state drawn in its platform's space onto that
    platform's copy as it was last placed, so a rider stands on the
    platform drawn. False while no copy of its platform has a place
--]]

function Playback.ride(state: StepState): boolean
	local id: number = state.platform
	if id == 0 then
		return true
	end

	local copy: vector? = ClientPlatforms.position(id)
	if copy == nil then
		return false
	end

	state.position += copy

	return true
end

-- The aim pitch a look direction gives, radians, up positive
function Playback.pitchOf(look: vector): number
	return math.asin(math.clamp(look.y, -1, 1))
end

--- Draws the clip at once as it stood a time after its keyframe: every
--- character the target was sent at the target's view of them, the target
--- at its own OwnerStates, its eye and look, and the platforms' copies. A
--- time past either end draws that end, and each render depends on its
--- time alone, so play, pause, single steps, slow motion and seeks are the
--- caller's. Forward play raises the footsteps it passes.
--- @method render
--- @within Playback
--- @param time number -- Seconds since the keyframe's tick

function Playback.render(self: Self, time: number)
	if self._ended then
		error("playback:render ran after playback:destroy ended the playback", 2)
	elseif type(time) ~= "number" or time - time ~= 0 then
		error(`playback:render takes a finite time in seconds, not {time}`, 2)
	end

	local clamped: number = math.clamp(time, 0, self._length)
	local relay: number = self._rate
	local clip: number = self._start + clamped * relay
	local previous: number? = self._time

	-- 1) Play or a seek: forward play within a second raises the footsteps it passes, and anything else is a seek
	if previous ~= nil then
		local moved: number = clamped - previous

		if moved < 0 or moved > SEEK then
			self._seeked = true
		elseif moved > 0 then
			self:_hear(self._start + previous * relay, clip)
		end
	end

	self._time = clamped
	self._renders += 1

	-- 2) The target's view: its drawn tick, the render time, the clip's platforms there and the eye
	local drawn: number, lag: number = self:_timing(clip)
	local at: number = drawn / self._share - lag
	local server: number = drawn + self._offset
	local world: World = self._world
	world.clock = math.floor(server)
	world.tick = world.clock % WRAP
	ClientPlatforms.frame(world, server)

	local target: number? = self:_view(clip, drawn)
	local rigs: Rigs.Rigs = self._rigs
	local eye: vector = self._eye
	local own: number? = nil

	-- 3) The target's rig at its own state, as a spectated target's world rig is drawn
	if target ~= nil then
		local slot: number, generation: number = Record.split(target)
		local shown: Drawn? = self:_out(slot, generation, "Player", false, clip)
		own = slot

		if shown then
			if self._watched ~= slot then
				self._watched = slot
				rigs:watch(slot)
			end

			local body: StepState = self._target
			rigs:pose(slot, body, vector.magnitude(body.position - eye), Playback.pitchOf(self._look))
		end
	end

	-- 4) Every other character open at the clip tick, from the newest samples that had arrived, at the render time
	local limits: Limits = self._limits
	for _, track: Track in self._tracks do
		local slot: number = track.slot
		local note: Mark? = markAt(track.marks, clip)

		if slot ~= own and note and note.open then
			local kept: Drawn? = self:_out(slot, note.generation, note.kind, note.withheld, clip)

			if kept then
				self:_outline(slot, kept, note.kind == "Player")

				local state: StepState = kept.state
				local shown: boolean = false
				local pitch: number = 0
				local headYaw: number = 0
				local headPitch: number = 0
				local newest: number = latest(track.ticks, clip)

				if newest >= note.first then
					local base: number = math.max(note.first, newest - WINDOW + 1)
					local count: number = newest - base + 1

					if note.kind == "Sleeper" or note.kind == "Body" then
						shown = lie(track, note, base, newest, at, clip, limits, state)
					else
						shown, pitch, headYaw, headPitch = Interpolate.sample(
							track.sampleTicks,
							track.sampleRecords,
							base - 1,
							count - 1,
							count,
							at,
							state
						)
					end
				end

				if shown and Playback.ride(state) then
					-- The head offset turns the neck as the live client turns it, held to the head cone
					local cone: number = limits.headCone
					local turnYaw: number = math.rad(math.clamp(headYaw, -cone, cone))
					local turnPitch: number = math.rad(math.clamp(headPitch, -cone, cone))
					rigs:turn(slot, turnYaw, turnPitch)
					rigs:pose(slot, state, vector.magnitude(state.position - eye), pitch)
					kept.shown = true
				elseif kept.shown then
					rigs:pose(slot, state, UNSEEN, 0)
					kept.shown = false
				end
			end
		end
	end

	-- 5) Every rig this render didn't keep goes back to the pool
	for slot: number, kept: Drawn in self._drawn do
		if kept.seen ~= self._renders then
			self:_release(slot, kept)
		end
	end
end

-- Raises each footstep a block brought after one clip tick and by another, oldest first
function Playback._hear(self: Self, from: number, to: number)
	local steps: { Footstep } = self._steps
	local ticks: { number } = self._stepTicks
	local heard: (step: Footstep) -> () = self._settings.heard

	for index: number = latest(ticks, from) + 1, #ticks do
		if ticks[index] > to then
			break
		end

		heard(steps[index])
	end
end

--[[
    Draws the target and its eye at a clip tick from the two OwnerStates
    around it, its look the newest stepped command's at or before the drawn
    tick, and gives the target's character while the newest frame by then
    carries its OwnerState; before the first OwnerState the eye stays where
    it was last drawn and nil is given
--]]

function Playback._view(self: Self, clip: number, drawn: number): number?
	local owners: { Owner } = self._owners
	local index: number = latest(self._ownerTicks, clip)
	if index == 0 then
		return nil
	end

	local older: Owner = owners[index]
	local newer: Owner? = owners[index + 1]
	local target: StepState = self._target
	if newer and newer.id == older.id then
		Playback.between(older.state, newer.state, (clip - older.tick) / (newer.tick - older.tick), target)
	else
		State.copy(older.state, target)
	end

	local world: World = self._world
	local cone: number = world.settings.headCone
	local stepped: number = latest(self._commandTicks, math.floor(drawn))
	self._eye = Eye.clear(target, world)

	if stepped > 0 then
		local look: Look = self._commands[stepped]
		self._look = Public.look(look.yaw, look.pitch, look.headYaw, look.headPitch, cone)
	else
		self._look = Public.look(target.facing, 0, 0, 0, cone)
	end

	if not self._owned[latest(self._frameTicks, clip)] then
		return nil
	end

	return older.id
end

--[[
    Keeps a clip rig out for a slot's life at a clip tick: one checked out
    from the pool, dressed and holding as that life's newest parts by then
    say, a rig of another life given back first, and its slot's kind and
    withholding as they stand. Nil when the dress hook threw, so the next
    render tries again
--]]

function Playback._out(
	self: Self,
	slot: number,
	generation: number,
	kind: Kind,
	withheld: boolean,
	clip: number
): Drawn?
	local rigs: Rigs.Rigs = self._rigs
	local track: Track? = self._tracked[slot]
	local look: Part? = nil
	local held: Part? = nil
	if track then
		look = partAt(track.looks, track.lookTicks, generation, clip)
		held = partAt(track.helds, track.heldTicks, generation, clip)
	end

	local kept: Drawn? = self._drawn[slot]
	if kept and kept.generation ~= generation then
		self:_release(slot, kept)
		kept = nil
	end

	if kept == nil then
		local outfit: Values = look and look.values or {}
		local checked: boolean, rig: Model? = xpcall(rigs.checkout, warnHook, rigs, slot, outfit, false)
		if not checked or not rig then
			return nil
		end

		local values: Values? = held and held.values
		if values then
			xpcall(rigs.hold, warnHook, rigs, slot, values)
		end

		local entry: Slot = { id = slot, kind = kind, player = nil, withheld = withheld }
		local made: Drawn = {
			slot = entry,
			generation = generation,
			look = look,
			held = held,
			shown = false,
			outlined = false,
			state = State.new(),
			seen = self._renders,
		}

		self._drawn[slot] = made
		self._settings.spawned(entry, rig)

		return made
	end

	local drawn: Drawn = kept
	drawn.seen = self._renders
	drawn.slot.kind = kind
	drawn.slot.withheld = withheld

	if look ~= drawn.look then
		drawn.look = look
		xpcall(rigs.dress, warnHook, rigs, slot, look and look.values or {})
	end

	if held ~= drawn.held then
		drawn.held = held
		xpcall(rigs.hold, warnHook, rigs, slot, held and held.values)
	end

	return drawn
end

-- Draws a clip rig under the spectate outline or out of it, telling the pool only of a change
function Playback._outline(self: Self, slot: number, drawn: Drawn, outlined: boolean)
	if drawn.outlined == outlined then
		return
	end

	drawn.outlined = outlined
	xpcall(self._rigs.outline, warnHook, self._rigs, slot, outlined)
end

-- Gives a clip rig back to the pool and tells the despawn
function Playback._release(self: Self, slot: number, drawn: Drawn)
	self._drawn[slot] = nil
	if self._watched == slot then
		self._watched = nil
	end

	xpcall(self._rigs.release, warnHook, self._rigs, slot)
	self._settings.despawned(drawn.slot)
end

--[[
    Sets the pool's track speed once a rendered frame: the clip seconds its
    renders moved over the frame's own, so a pause holds every rig still
    and slow motion slows them, while a seek, a jump past a second or a
    frame of no time keeps the speed it had
--]]

function Playback.frame(self: Self, dt: number)
	local time: number? = self._time
	if self._ended or time == nil then
		return
	end

	local framed: number? = self._framed
	local seeked: boolean = self._seeked
	self._framed = time
	self._seeked = false

	if framed == nil or seeked or not (dt > 0) then
		return
	end

	local moved: number = time - framed
	if moved < 0 or moved > SEEK then
		return
	end

	local speed: number = moved / dt
	if speed ~= self._speed then
		self._speed = speed
		self._rigs:setSpeed(speed)
	end
end

-- The eye and look the last render drew, or where the eye was before any drew one
function Playback.eye(self: Self): (vector, vector)
	return self._eye, self._look
end

-- The slot a clip rig is drawn for, the same table from its spawn to its despawn, nil for a slot with none
function Playback.slotOf(self: Self, slot: number): Slot?
	local drawn: Drawn? = self._drawn[slot]
	if drawn == nil then
		return nil
	end

	return drawn.slot
end

--- Ends the playback: every rig it drew goes back to the pool, each one's
--- despawn told, the pool's track speed is set back to each track's own,
--- and the live characters are drawn again. A second call errors.
--- @method destroy
--- @within Playback

function Playback.destroy(self: Self)
	if self._ended then
		error("playback:destroy ends a playback once, and this one has ended", 2)
	end

	self._ended = true

	for slot: number, drawn: Drawn in self._drawn do
		self:_release(slot, drawn)
	end

	if self._speed ~= AUTHORED then
		self._speed = AUTHORED
		self._rigs:setSpeed(AUTHORED)
	end

	self._settings.ended()
end

--- @class Playback
--- A moderator's clip the client plays, from client:play: rendered at the
--- caller's clip time, and ended with destroy.

export type Playback = Self
type Self = typeof(setmetatable({} :: Fields, Playback))

return Playback
