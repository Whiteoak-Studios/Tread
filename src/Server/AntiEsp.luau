--[[
    Anti-ESP: which characters each viewer may be sent, tested with rays
    from its cleared eye on the schedules the server settings give, a slice
    at a time inside a budget, the rays cast here or on its Actor workers
--]]

--!strict
--!native
local AntiEspWorkers = require(script.Parent.AntiEspWorkers)
local Casts = require(script.Parent.AntiEspWorkers.Casts)
local Config = require(script.Parent.Parent.Config)
local Connections = require(script.Parent.Connections)
local Constants = require(script.Parent.Parent.Constants)
local Eye = require(script.Parent.Parent.Step.Eye)
local Math = require(script.Parent.Parent.Step.Math)
local Relay = require(script.Parent.Relay)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local Tap = require(script.Parent.Parent.Codec.Tap)

local SLOTS: number = Constants.SLOTS
local PLAYER_RAYS: number = Constants.PLAYER_RAYS -- The rays a player pair's test has
local LYING_RAYS: number = Constants.LYING_RAYS -- A sleeper's or body's
local NONE: number = 0 -- No pair, group, kind or heap, in every index and link
local DUE_NOW: number = -math.huge -- A due time every slice has reached
local ACROSS: vector = vector.create(1, 0, 0) -- The side points' axis toward a target straight above or below the eye
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row
local ROW_BYTES: number = SLOTS // BITS -- A viewer's row of answers, one bit a slot
local NO_TEAM: number = 0 / 0 -- An answered team for none, which equals no team, itself included
local BOX_BYTES: number = Casts.BOX_BYTES -- A kept box's
local BOX_GROWTH: number = 2 -- How many times larger the kept boxes' buffer grows once a pair's box passes its end
local DRAIN_CHECK: number = 16 -- Entries a drain takes between its reads of the clock while the slice runs whole

-- A slot's kind as anti-ESP keeps it
local PLAYER: number = 1
local LYING: number = 2 -- A sleeper or a body
local NPC: number = 3
local KIND_CODES: { [string]: number } = { Player = PLAYER, Sleeper = LYING, Body = LYING, Npc = NPC }

-- A sleeper group's state
local WAITING: number = 1 -- Its viewer is within the retest distance of where it stood at the group's tests
local TIMED: number = 2 -- Its viewer walked past that before the rate allowed, so a timer waits for the rate
local TRIGGERED: number = 3 -- Its viewer walked past it with the rate allowing, so its pairs went due

-- The due heap a waiting pair is in
local HIDDEN_DUE: number = 1
local VISIBLE_DUE: number = 2
local LYING_DUE: number = 3

-- A pair's verdict, why it is sent or why not, every one that hides it at HIDDEN or above, so one compare answers
local CLEAR: number = 1 -- Its last test found a ray open
local HOLD: number = 2 -- Its last test found every ray blocked, inside the hold since a test found it open
local FAIL_OPEN: number = 3 -- It went untested past the fail-open time while hidden, and is sent untested since
local HIDDEN: number = 4 -- Its last test found every ray blocked past the hold
local UNTESTED: number = 5 -- A new pair or a new life, hidden until its first test
local VERDICTS: { Reason } = { "Clear", "Hold", "FailOpen", "Hidden", "Untested" } -- Each verdict's send reason

type AimPoint = Config.AimPoint
type AimPoints = Config.AimPoints
type Blocked = Casts.Blocked
type Bot = { Name: string }
type Entry = Slots.Entry
type Key = Player | Bot
type LyingBox = State.LyingBox
type Met = Casts.Met
type Posture = State.Posture
type Query = Casts.Query
type Reason = Tap.Reason
type ServerSettings = Config.ServerSettings
type Settings = State.Settings
type Shared = Config.Shared
type State = State.State
type Viewer = Relay.Viewer
type World = State.World

-- What isHidden would answer for each viewer handed to AntiEsp.answers, each buffer reused by its next call
export type Answers = {
	kinds: buffer, -- u8 by slot: 0 free, 1 player, 2 sleeper or body, 3 NPC
	teams: buffer, -- f64 by slot: the team its current life carries, NaN for none
	visible: buffer, -- A row of ROW_BYTES by each viewer's place in the list from 0: bit slot % 8 of byte slot // 8
	quiet: buffer, -- Laid out as visible: set where an ask would only stamp its pair asked, read as if no team matched
}

-- What anti-ESP keeps for one viewer, made at its first pair and reused for another once it leaves
type Sight = {
	viewer: Viewer, -- The table the relay last asked with, which the server handle refills each relay tick
	live: boolean, -- False once it leaves, until another viewer takes its place
	targets: buffer, -- u32: its pair with each slot, NONE for none
	slice: number, -- The slice its eye was last found in
	eye: vector, -- Where its rays start this slice: its cleared eye, or where it stands while it has no body
	drift: vector, -- How far its body moves over the look-ahead
	stamp: number, -- Moves on while verdict memory is on whenever a slice finds its eye or drift otherwise
	lookAhead: number, -- Its round trip held to the settings' clamp, in seconds
	cleared: vector, -- Its body's cleared eye, kept through the world's tick it was found on
	clearedFor: State?, -- The body it was found for, nil until one is found and once a move drops it
	clearedTick: number, -- The world's unwrapped tick it was found on
	clearedChanges: number, -- And the body's slot's changes in the slot table then
	groups: number, -- The first of its sleeper groups, NONE for none
	group: number, -- The group its sleeper pairs tested in groupSlice joined
	groupSlice: number,
	anchor: vector, -- Where it stood when its groups were last measured
	margin: number, -- How far it may walk from there before any waiting group of its could be due
	dirty: boolean, -- A group of its went back to waiting, so its groups are measured again
}

-- One schedule's entries in due order, each a pair and the stamp it was scheduled under
type Queue = {
	ids: { number },
	stamps: { number },
	times: { number },
	head: number, -- The first entry not yet taken
	tail: number, -- The last entry, below head while it is empty
}

-- A heap of entries, the lowest key first, each an id and the stamp it was added under
type Heap = {
	ids: { number },
	stamps: { number },
	keys: { number },
	count: number,
	stale: number, -- Entries whose pair has a newer stamp, which a due heap is cleared of once they outnumber the rest
}

-- One posture's aim points as a test reads them, each field an array by the point's place in the settings' list
type Aim = {
	ups: { number }, -- Studs above the feet
	sides: { number }, -- Studs to the viewer's right, across the line from its eye to the target
	leads: { boolean }, -- Cast from the eye moved over the look-ahead to the end moved by the target's velocity
	count: number,
}

-- What verdict memory keeps for each player pair, each field an array by the pair's index
type Memory = {
	sights: { number }, -- Its viewer's sight's stamp when its rays were last aimed
	slots: { number }, -- And its target's slot's
	epochs: { number }, -- The geometry epoch its kept answer holds for, NONE for no answer
	opens: { boolean }, -- That answer: whether a ray was open
	aimed: { number }, -- The epoch its rays were last aimed under, which a worker's answer holds for once it lands
	boxEpochs: { number }, -- The epoch its kept box was learned under, NONE for none
	boxes: buffer, -- Its box at BOX_BYTES a pair from its index less 1, grown as boxes are kept
}

-- Each slot's target as verdict memory's last test of it saw it, each field an array by the slot plus 1
type Standings = {
	stamps: { number }, -- Moves on whenever a test finds it otherwise
	positions: { vector },
	velocities: { vector },
	postures: { Posture },
	swims: { boolean },
}

-- A slice running whole, which stops each of its four steps at its deadline, and where a cut left them
type WholeState = {
	on: boolean,
	from: number, -- The step the next slice begins at, its place in Steps: the first unless the last slice was cut
	walk: number, -- The place in Sights the walk starts from, where a cut walk stopped, 1 once a walk ends
	drain: number, -- The place in Queues the drains start from, the queue after a cut one, 1 once the drains end
	cuts: number, -- The slices the deadline cut short, since start, as AntiEsp.cuts gives them
}

-- One of a slice's four steps, run on the schedule's clock with what falls due by due, stopping at the deadline while
-- whole. It gives whether the deadline stopped it with work left, whether it took any item first, and whether that
-- counts the slice as cut
type Step = (world: World, now: number, due: number, deadline: number, whole: boolean) -> (boolean, boolean, boolean)

-- The tests a packing slice answered here, which land beside its batches at the next slice, as theirs would
type Pending = {
	pairs: { number },
	stamps: { number },
	opens: { boolean },
	kept: { boolean }, -- Whether a kept answer gave it, counted as a kept test once it lands
	count: number,
	sent: number, -- The first this many reached the slice's send, and the rest are made due again
	reach: number, -- The clock that send's results settle on
	at: number, -- And the schedule's clock at it, from which they are given up past the fail-open time
}

local Started: boolean = false

-- What start hands in
local Space: World? = nil -- The server's world, whose casts clear each viewer's eye
local Bodies: { [number]: State } = {} -- The server's states by slot, read where they stand at each test
local Clock: () -> number = os.clock -- Seconds, which each slice's deadline and its tests' means are read on

-- Whiteoak TODO: a custom terrain route's heightfield joins these rays through the game's cast wrapper once that
-- route exists; until then they meet only what blocked casts against. An Actor worker can't call a game's own cast
-- function, so with antiEsp.workers that route needs another answer for the rays the workers cast
local Blocked: Blocked = function (_: vector, _: vector): boolean
	error("AntiEsp casts no ray until AntiEsp.start hands it blocked")
end

-- The same test giving what a ray met, which verdict memory asks of only a ray whose hit it may keep as a box
local Occluder: Query = Blocked

-- The Actor workers antiEsp.workers starts, and whether the slices pack for them, which a dev bench can flip
local Pooled: boolean = false -- Whether any were started, so every slice brings in what they landed
local UseWorkers: boolean = false
local Packing: boolean = false -- Whether the slice running packs its tests for them in place of casting them

-- The server settings as the slices read them, each rate as the seconds between tests
local Aims: { [Posture]: Aim } = {}
local LyingRays: number = 0
local LookAheadMin: number = 0
local LookAheadMax: number = 0
local HiddenInterval: number = 0
local NearInterval: number = 0 -- A hidden pair's, while its target is within NearSquared of the viewer's eye
local NearSquared: number = 0
local VisibleInterval: number = 0
local Hold: number = 0
local FailOpen: number = 0
local Retest: number = 0
local RetestSquared: number = 0
local LyingInterval: number = 0
local LyingHold: number = 0
local LyingShare: number = 0 -- Seconds of each slice its sleeper and body pairs are tested for first
local RelayInterval: number = 0 -- Seconds a relay tick takes, the most a packing slice reaches ahead

local Now: number = 0 -- The schedule's clock at the last slice, which an ask's fail-open is measured on
local Slice: number = 0 -- The slices run since start
local Round: number = 0 -- The relay's runs that asked about a pair
local Ran: boolean = true -- Whether a slice ran since the relay last asked, so its next ask starts a round

-- Whether each slice's timers, walks and drains stop at its deadline as its tests do, and where the last cut left them
local Whole: WholeState = { on = false, from = 1, walk = 1, drain = 1, cuts = 0 }

-- This slice's tests of each kind, a sleeper's or body's and a player's, and the seconds they took, for their means
local LyingRun: number = 0
local LyingTook: number = 0
local PlayerRun: number = 0
local PlayerTook: number = 0

-- Since start, for the server's stats
local Tests: number = 0
local HiddenResults: number = 0 -- Tests that left their pair hidden
local FailOpens: number = 0

local LyingTests: number = 0 -- Sleepers' and bodies' pair tests since AntiEsp.lying last gave them
local Rays: number = 0 -- The rays cast on the engine, here and on the workers, since AntiEsp.rays last gave them

-- Verdict memory, a dev bench's switch: a player pair's last answer kept while nothing its rays are aimed from has
-- moved, and the box of the Block part that last blocked it tested ahead of the engine. Each holds only for the
-- geometry epoch it was found under, which moves on at every change to the include list it hears
local Remembering: boolean = false
local Epoch: number = 1
local Kept: Memory = {
	sights = {},
	slots = {},
	epochs = {},
	opens = {},
	aimed = {},
	boxEpochs = {},
	boxes = buffer.create(0),
}
local Standing: Standings =
	{ stamps = table.create(SLOTS, 0), positions = {}, velocities = {}, postures = {}, swims = {} }
local Deferred: Pending = { pairs = {}, stamps = {}, opens = {}, kept = {}, count = 0, sent = 0, reach = 0, at = 0 }
local KeptTests: number = 0 -- Tests a kept answer settled since start, each counted where it is applied
local BoxRays: number = 0 -- Rays a kept box blocked with no engine ray cast, since start
local Include: { Instance } = {} -- The include list as start found it

-- Owned by verdict memory's switch: useMemory(true) connects each include instance's DescendantAdded,
-- DescendantRemoving and AncestryChanged to move the epoch on, and useMemory(false) disconnects every one, so
-- none is connected while memory is off
local Watching: { RBXScriptConnection } = {}

-- Each slot's kind and generation by its slot plus 1, kept from the slot table's changes, so an ask calls nothing
local KindOf: { number } = table.create(SLOTS, NONE)
local LifeOf: { number } = table.create(SLOTS, 0)
local ChangesOf: { number } = table.create(SLOTS, 0) -- Its changes since start, after which a kept eye is found again

-- Each slot's team, kept with the life it was given for
local TeamValues: buffer = buffer.create(SLOTS * 8) -- f64
local TeamLives: buffer = buffer.create(SLOTS) -- u8: the generation plus 1 it was set for, 0 for none

local SightOf: { [Key]: number } = {} -- Each viewer's place in Sights
local Sights: { Sight } = {}
local FreeSights: { number } = {}

-- The viewer the relay is asking about, and what its asks read, found once a viewer a run
local Asker: Viewer? = nil
local AskerIndex: number = NONE
local AskerTargets: buffer = buffer.create(0)
local AskerTeam: number? = nil

-- While a relay round is out, every change to anti-ESP's state made since its hold, run in arrival order at its release
local Holding: boolean = false
local Held: { () -> () } = {}

-- What AntiEsp.answers hands out, and each asked viewer's row's first byte by its place in Sights while it runs
local Answered: Answers = {
	kinds = buffer.create(SLOTS),
	teams = buffer.create(SLOTS * 8),
	visible = buffer.create(0),
	quiet = buffer.create(0),
}
local RowOf: { [number]: number } = {}
local AnsweredAt: number = -1 -- The slice count the last answers were made at, -1 before any, as a slice can move a bit

-- Every pair by its index, each field an array, and the indexes a dropped pair left free
local PairSights: { number } = {} -- Its viewer's place in Sights, NONE while free
local PairSlots: { number } = {} -- Its target's slot
local PairLives: { number } = {} -- And the target's generation
local PairLying: { boolean } = {} -- A sleeper or body, on the sleepers' schedule
local PairVerdicts: { number } = {} -- Why it is sent, or why not
local PairChecked: { number } = {} -- When it was last tested, made or moved to another schedule
local PairSeen: { number } = {} -- When a test last found it visible, -math.huge for never
local PairAsked: { number } = {} -- The round the relay last asked about it
local PairStamps: { number } = {} -- Moves on at each change of its schedule, so only its newest entry counts
local PairHeaped: { number } = {} -- The due heap it waits in under its stamp, NONE for none
local PairGroups: { number } = {} -- The sleeper group it was last tested in, NONE for none
local PairNext: { number } = {} -- Its neighbors in that group
local PairPrevious: { number } = {}
local FreePairs: { number } = {}
local PairTop: number = 0 -- The highest index ever made

-- Each sleeper group by its index: one viewer's sleeper pairs tested in one slice, which share where it stood then
local GroupSights: { number } = {} -- Its viewer's place in Sights, NONE while free
local GroupFrom: { vector } = {}
local GroupChecked: { number } = {}
local GroupStates: { number } = {}
local GroupStamps: { number } = {} -- Moves on when it is freed, so no timer holds it after
local GroupFirst: { number } = {} -- Its first pair
local GroupNext: { number } = {} -- Its neighbors among its viewer's groups
local GroupPrevious: { number } = {}
local FreeGroups: { number } = {}
local GroupTop: number = 0

-- The schedules whose due times nearly always come in the order they are set, as the schedule's clock never runs
-- back but for a worker's result settled on the clock it was aimed at, which goes in its place, so each interval
-- keeps a queue of its own
local NowQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local HiddenQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local NearQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local VisibleQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local Queues: { Queue } = { NowQueue, HiddenQueue, NearQueue, VisibleQueue } -- In the order a slice drains them

-- The sleepers' timers by time: a pair's id for a held retest, and a group's negated for its rate
local Timers: Heap = { ids = {}, stamps = {}, keys = {}, count = 0, stale = 0 }

-- The due pairs waiting to be tested, kept across slices: hidden player pairs by their squared distance when they
-- came due, and the visible and lying ones by when they were last tested
local HiddenDue: Heap = { ids = {}, stamps = {}, keys = {}, count = 0, stale = 0 }
local VisibleDue: Heap = { ids = {}, stamps = {}, keys = {}, count = 0, stale = 0 }
local LyingDue: Heap = { ids = {}, stamps = {}, keys = {}, count = 0, stale = 0 }
local Dues: { Heap } = { HiddenDue, VisibleDue, LyingDue }

-- One test's rays, refilled by each
local Origins: { vector } = table.create(PLAYER_RAYS, vector.zero)
local Ends: { vector } = table.create(PLAYER_RAYS, vector.zero)

local AntiEsp = {}

-- Keeps a slot's kind and generation as the slot table gives them, no kind for a free slot
local function note(slot: number, generation: number, entry: Entry?)
	local kind: number = NONE
	if entry ~= nil then
		kind = KIND_CODES[entry.kind]
	end

	KindOf[slot + 1] = kind
	LifeOf[slot + 1] = generation
	ChangesOf[slot + 1] += 1

	-- The next ask finds its viewer's own slot and team afresh, since two relay runs can come with no slice between
	Asker = nil
end

-- Moves the geometry epoch on, so verdict memory uses no answer or box found before it
local function shift()
	Epoch += 1
end

--[[
    A posture's aim points read into the arrays a test reads, refusing more
    than the rays a player pair's test has
--]]

local function aimOf(posture: Posture, points: AimPoints): Aim
	local count: number = #points
	if count > PLAYER_RAYS then
		error(`server.antiEsp.aim.{posture} is at most the {PLAYER_RAYS} rays a player pair's test has, not {count}`, 3)
	end

	local aim: Aim = { ups = {}, sides = {}, leads = {}, count = count }

	for index: number = 1, count do
		local point: AimPoint = points[index]
		aim.ups[index] = point.up
		aim.sides[index] = point.side
		aim.leads[index] = point.lead == true
	end

	return aim
end

--[[
    Starts anti-ESP with the game's checked tables, the server's world for
    each viewer's cleared eye, the states the server keeps by slot, blocked,
    true when a ray from origin along direction meets an occluder, and
    occluder, what such a ray meets, its instance or true, nil or false for
    none, which verdict memory alone asks, of a ray whose hit it may keep as
    a box; without it no box is kept. clock gives the seconds each slice's
    deadline is read on, os.clock when left out. Above 0, antiEsp.workers
    Actor workers cast its rays. It refuses more rays than a pair's test
    has, and runs once
--]]

function AntiEsp.start(
	settings: { shared: Shared, server: ServerSettings },
	world: World,
	states: { [number]: State },
	blocked: Blocked,
	occluder: Query?,
	clock: (() -> number)?
)
	if Started then
		error("AntiEsp.start runs once, and it has already run", 2)
	elseif type(settings) ~= "table" or type(world) ~= "table" or type(states) ~= "table" then
		error("AntiEsp.start takes the settings, the server's world and its states as tables", 2)
	elseif type(blocked) ~= "function" then
		error(`AntiEsp.start takes blocked as a function, not a {typeof(blocked)}`, 2)
	elseif occluder ~= nil and type(occluder) ~= "function" then
		error(`AntiEsp.start takes occluder as a function or nil, not a {typeof(occluder)}`, 2)
	elseif clock ~= nil and type(clock) ~= "function" then
		error(`AntiEsp.start takes clock as a function giving seconds or nil, not a {typeof(clock)}`, 2)
	end

	local server: ServerSettings = settings.server
	local aims: { [Posture]: Aim } = {
		Stand = aimOf("Stand", server.antiEsp.aim.Stand),
		Crouch = aimOf("Crouch", server.antiEsp.aim.Crouch),
		Downed = aimOf("Downed", server.antiEsp.aim.Downed),
	}

	local lyingRays: number = server.sleepers.rays
	if lyingRays > LYING_RAYS then
		error(`server.sleepers.rays is at most the {LYING_RAYS} rays a sleeper's test has, not {lyingRays}`, 2)
	end

	local workers: number = server.antiEsp.workers or 0
	if workers > 0 then
		AntiEspWorkers.start(workers, server.antiEsp.include, server.antiEsp.failOpen)
		Pooled = true
		UseWorkers = true
	end

	Started = true
	Space = world
	Bodies = states
	Blocked = blocked
	Occluder = occluder or blocked
	Clock = clock or os.clock
	Include = table.clone(server.antiEsp.include)

	Aims = aims
	LyingRays = lyingRays
	LookAheadMin = server.antiEsp.lookAheadMin
	LookAheadMax = server.antiEsp.lookAheadMax
	HiddenInterval = 1 / server.antiEsp.hiddenRate
	NearInterval = 1 / server.antiEsp.nearRate
	NearSquared = server.antiEsp.nearRadius ^ 2
	VisibleInterval = 1 / server.antiEsp.visibleRate
	Hold = server.antiEsp.hold
	FailOpen = server.antiEsp.failOpen
	Retest = server.sleepers.retest
	RetestSquared = Retest ^ 2
	LyingInterval = 1 / server.sleepers.rate
	LyingHold = server.sleepers.hold
	LyingShare = server.antiEsp.lyingShare
	RelayInterval = 1 / settings.shared.rates.relay

	for slot: number = 0, SLOTS - 1 do
		local generation: number, entry: Entry? = Slots.get(slot)
		note(slot, generation, entry)
	end

	-- Lives as long as the server, as anti-ESP does. The slot table never changes an entry it hands out, so a held
	-- change keeps its own
	Slots.onChange(function (slot: number, generation: number, _: Entry?, current: Entry?)
		if Holding then
			table.insert(Held, function ()
				note(slot, generation, current)
			end)
		else
			note(slot, generation, current)
		end
	end)
end

--[[
    Adds an entry at a queue's back, due no sooner than the entry before
    it, first moving what is left to the front once the entries taken
    outnumber it, so its arrays never grow far past the most it has held
--]]

local function enqueue(queue: Queue, id: number, stamp: number, time: number)
	local head: number = queue.head
	local tail: number = queue.tail
	local left: number = tail - head + 1

	if head > 1 and head - 1 >= left then
		table.move(queue.ids, head, tail, 1)
		table.move(queue.stamps, head, tail, 1)
		table.move(queue.times, head, tail, 1)
		head = 1
		queue.head = 1
		tail = left
	end

	-- A worker's answer settles on its batch's reach, a lead past the slice that packed it, which can pass the clock a
	-- later test settles on, so an entry due before the one ahead waits behind it, later by no more than a lead
	local times: { number } = queue.times
	if tail >= head and time < times[tail] then
		time = times[tail]
	end

	queue.ids[tail + 1] = id
	queue.stamps[tail + 1] = stamp
	times[tail + 1] = time
	queue.tail = tail + 1
end

-- Adds an entry to a heap, moving it up past every entry with a higher key
local function heapPush(heap: Heap, id: number, stamp: number, key: number)
	local ids: { number } = heap.ids
	local stamps: { number } = heap.stamps
	local keys: { number } = heap.keys
	local index: number = heap.count + 1
	heap.count = index

	while index > 1 do
		local parent: number = index // 2
		if keys[parent] <= key then
			break
		end

		ids[index] = ids[parent]
		stamps[index] = stamps[parent]
		keys[index] = keys[parent]
		index = parent
	end

	ids[index] = id
	stamps[index] = stamp
	keys[index] = key
end

-- Puts an entry at a heap's index or below it, each lower child moving up past it
local function sift(heap: Heap, index: number, id: number, stamp: number, key: number)
	local ids: { number } = heap.ids
	local stamps: { number } = heap.stamps
	local keys: { number } = heap.keys
	local count: number = heap.count

	while index * 2 <= count do
		local child: number = index * 2
		if child < count and keys[child + 1] < keys[child] then
			child += 1
		end

		if keys[child] >= key then
			break
		end

		ids[index] = ids[child]
		stamps[index] = stamps[child]
		keys[index] = keys[child]
		index = child
	end

	ids[index] = id
	stamps[index] = stamp
	keys[index] = key
end

-- Takes a heap's lowest entry off it, its last one sifted into its place
local function heapPop(heap: Heap)
	local last: number = heap.count
	heap.count = last - 1

	if last > 1 then
		sift(heap, 1, heap.ids[last], heap.stamps[last], heap.keys[last])
	end
end

-- Clears a due heap of its stale entries and orders what is left again
local function compact(heap: Heap)
	local ids: { number } = heap.ids
	local stamps: { number } = heap.stamps
	local keys: { number } = heap.keys
	local kept: number = 0

	for index: number = 1, heap.count do
		local pair: number = ids[index]
		if PairStamps[pair] == stamps[index] then
			kept += 1
			ids[kept] = pair
			stamps[kept] = stamps[index]
			keys[kept] = keys[index]
		end
	end

	heap.count = kept
	heap.stale = 0

	for index: number = kept // 2, 1, -1 do
		sift(heap, index, ids[index], stamps[index], keys[index])
	end
end

--[[
    Moves a pair's stamp on, so every entry it held goes stale, counting
    the one it waits in a due heap with, and gives the new stamp
--]]

local function restamp(pair: number): number
	local heaped: number = PairHeaped[pair]
	if heaped ~= NONE then
		Dues[heaped].stale += 1
		PairHeaped[pair] = NONE
	end

	local stamp: number = PairStamps[pair] + 1
	PairStamps[pair] = stamp

	return stamp
end

-- Gives a pair a new place on a schedule, which every older entry of its no longer holds
local function schedule(pair: number, queue: Queue, time: number)
	enqueue(queue, pair, restamp(pair), time)
end

-- Frees an emptied sleeper group, which no timer holds once its stamp moves on
local function dissolve(group: number)
	local sight: Sight = Sights[GroupSights[group]]
	local previous: number = GroupPrevious[group]
	local following: number = GroupNext[group]

	if previous ~= NONE then
		GroupNext[previous] = following
	else
		sight.groups = following
	end

	if following ~= NONE then
		GroupPrevious[following] = previous
	end

	if sight.group == group then
		sight.groupSlice = 0
	end

	GroupStamps[group] += 1
	GroupSights[group] = NONE
	table.insert(FreeGroups, group)
end

-- Takes a pair out of its sleeper group, freeing the group once it is empty
local function unlink(pair: number)
	local group: number = PairGroups[pair]
	if group == NONE then
		return
	end

	local previous: number = PairPrevious[pair]
	local following: number = PairNext[pair]

	if previous ~= NONE then
		PairNext[previous] = following
	else
		GroupFirst[group] = following
	end

	if following ~= NONE then
		PairPrevious[following] = previous
	end

	PairGroups[pair] = NONE

	if GroupFirst[group] == NONE then
		dissolve(group)
	end
end

-- Puts a pair first in a sleeper group
local function join(pair: number, group: number)
	local first: number = GroupFirst[group]
	PairGroups[pair] = group
	PairPrevious[pair] = NONE
	PairNext[pair] = first

	if first ~= NONE then
		PairPrevious[first] = pair
	end

	GroupFirst[group] = pair
end

--[[
    The group a viewer's sleeper pairs tested in this slice join, made at
    the first of them where the viewer stands now, which narrows how far it
    may walk before its groups are measured again
--]]

local function groupFor(index: number, sight: Sight, now: number): number
	if sight.groupSlice == Slice then
		return sight.group
	end

	local from: vector = sight.viewer.position
	local group: number = GroupTop + 1
	local reused: number? = table.remove(FreeGroups)

	if reused ~= nil then
		group = reused
	else
		GroupTop = group
		GroupStamps[group] = 0
	end

	local first: number = sight.groups
	GroupSights[group] = index
	GroupFrom[group] = from
	GroupChecked[group] = now
	GroupStates[group] = WAITING
	GroupFirst[group] = NONE
	GroupPrevious[group] = NONE
	GroupNext[group] = first

	if first ~= NONE then
		GroupPrevious[first] = group
		sight.margin = math.max(math.min(sight.margin, Retest - vector.magnitude(from - sight.anchor)), 0)
	else
		sight.anchor = from
		sight.margin = Retest
	end

	sight.groups = group
	sight.group = group
	sight.groupSlice = Slice

	return group
end

-- Frees a pair's index, its place in its viewer's targets and in its group, and every entry it held
local function release(pair: number)
	unlink(pair)
	restamp(pair)

	local sight: Sight = Sights[PairSights[pair]]
	buffer.writeu32(sight.targets, PairSlots[pair] * 4, NONE)

	PairSights[pair] = NONE
	table.insert(FreePairs, pair)
end

--[[
    Lets one due pair wait in its due heap, unless it waits there already.
    One the relay didn't ask about on its last run, or whose target is gone
    from the states, is dropped untested
--]]

local function admit(pair: number)
	if PairHeaped[pair] ~= NONE then
		return
	end

	local target: State? = Bodies[PairSlots[pair]]
	if target == nil or PairAsked[pair] ~= Round then
		release(pair)

		return
	end

	local stamp: number = PairStamps[pair]

	if PairLying[pair] then
		heapPush(LyingDue, pair, stamp, PairChecked[pair])
		PairHeaped[pair] = LYING_DUE
	elseif PairVerdicts[pair] >= HIDDEN then
		local offset: vector = target.position - Sights[PairSights[pair]].viewer.position
		heapPush(HiddenDue, pair, stamp, vector.dot(offset, offset))
		PairHeaped[pair] = HIDDEN_DUE
	else
		heapPush(VisibleDue, pair, stamp, PairChecked[pair])
		PairHeaped[pair] = VISIBLE_DUE
	end
end

-- Every pair of a group its viewer walked past with the rate allowing goes due, and the group is spent
local function trigger(group: number)
	GroupStates[group] = TRIGGERED

	local pair: number = GroupFirst[group]
	while pair ~= NONE do
		local following: number = PairNext[pair]
		admit(pair)
		pair = following
	end
end

--[[
    Measures where a viewer stands against each of its waiting groups: one
    walked past the retest distance triggers, or waits on a timer for the
    rate when it was tested too lately, and the nearest any other comes to
    it is how far the viewer may walk before they are measured again
--]]

local function measure(sight: Sight, position: vector, now: number)
	local margin: number = math.huge
	local group: number = sight.groups

	-- Each group of the viewer's once, as the list ends at NONE
	while group ~= NONE do
		local following: number = GroupNext[group]

		if GroupStates[group] == WAITING then
			local walked: vector = position - GroupFrom[group]
			local squared: number = vector.dot(walked, walked)

			if squared <= RetestSquared then
				margin = math.min(margin, Retest - math.sqrt(squared))
			elseif now - GroupChecked[group] >= LyingInterval then
				trigger(group)
			else
				GroupStates[group] = TIMED
				heapPush(Timers, -group, GroupStamps[group], GroupChecked[group] + LyingInterval)
			end
		end

		group = following
	end

	sight.anchor = position
	sight.margin = margin
	sight.dirty = false
end

-- The team a slot's current life was given, nil for none
local function teamOf(slot: number, generation: number): number?
	if buffer.readu8(TeamLives, slot) ~= generation + 1 then
		return nil
	end

	return buffer.readf64(TeamValues, slot * 8)
end

-- A viewer's place in Sights and what anti-ESP keeps for it, made or reused at its first ask
local function sightOf(viewer: Viewer): (number, Sight)
	local key: Key = viewer.key
	local index: number? = SightOf[key]
	if index ~= nil then
		local kept: Sight = Sights[index]
		kept.viewer = viewer

		return index, kept
	end

	local made: number = #Sights + 1
	local sight: Sight
	local reused: number? = table.remove(FreeSights)

	if reused ~= nil then
		made = reused
		sight = Sights[made]
		sight.viewer = viewer
		sight.live = true
		sight.slice = 0
		sight.groups = NONE
		sight.groupSlice = 0
		sight.margin = math.huge
		sight.dirty = false
	else
		sight = {
			viewer = viewer,
			live = true,
			targets = buffer.create(SLOTS * 4),
			slice = 0,
			eye = vector.zero,
			drift = vector.zero,
			stamp = 0,
			lookAhead = 0,
			cleared = vector.zero,
			clearedFor = nil :: State?,
			clearedTick = 0,
			clearedChanges = 0,
			groups = NONE,
			group = NONE,
			groupSlice = 0,
			anchor = vector.zero,
			margin = math.huge,
			dirty = false,
		}
		Sights[made] = sight
	end

	SightOf[key] = made

	return made, sight
end

--[[
    Finds what the relay's asks about one viewer read, once a viewer a run:
    its place, its pairs by slot and its own character's team, for the
    life the slot table's changes last gave anti-ESP, which a hold keeps
--]]

local function attend(viewer: Viewer)
	local index: number, sight: Sight = sightOf(viewer)
	local own: number? = viewer.slot

	AskerTeam = nil
	if own ~= nil then
		AskerTeam = teamOf(own, LifeOf[own + 1])
	end

	Asker = viewer
	AskerIndex = index
	AskerTargets = sight.targets
end

-- Drops what verdict memory keeps for a pair, whose new life, new kind or new use of its index reads none of it
local function unkeep(pair: number)
	Kept.epochs[pair] = NONE
	Kept.boxEpochs[pair] = NONE
end

-- A pair as each life starts it: hidden, never seen and due at once, its fail-open counted from now
local function fresh(pair: number, generation: number, lying: boolean)
	unlink(pair)

	if Remembering then
		unkeep(pair)
	end

	PairLives[pair] = generation
	PairLying[pair] = lying
	PairVerdicts[pair] = UNTESTED
	PairChecked[pair] = Now
	PairSeen[pair] = -math.huge

	schedule(pair, NowQueue, DUE_NOW)
end

--[[
    A pair whose target fell asleep or woke within its life: it keeps its
    verdict and is retested at once on its new schedule, its fail-open
    counted from now, so a sleeper long untested that wakes doesn't fail
    open before its first test as a player
--]]

local function rekind(pair: number, lying: boolean)
	PairLying[pair] = lying
	PairChecked[pair] = Now

	if not lying then
		unlink(pair)
	end

	if Remembering then
		unkeep(pair)
	end

	schedule(pair, NowQueue, DUE_NOW)
end

-- Makes a pair for a viewer and a slot at a free index, or a new one past the highest
local function place(index: number, targets: buffer, slot: number, generation: number, lying: boolean): number
	local pair: number = PairTop + 1
	local reused: number? = table.remove(FreePairs)

	if reused ~= nil then
		pair = reused
	else
		PairTop = pair
		PairStamps[pair] = 0
		PairHeaped[pair] = NONE
		PairGroups[pair] = NONE
		PairNext[pair] = NONE
		PairPrevious[pair] = NONE
	end

	PairSights[pair] = index
	PairSlots[pair] = slot
	PairAsked[pair] = Round
	fresh(pair, generation, lying)

	buffer.writeu32(targets, slot * 4, pair)

	return pair
end

--[[
    Whether anti-ESP hides a slot from a viewer, which the relay asks once a
    run for each pair relevant to it and not Invisible. An NPC is never
    hidden, nor a player who carries the viewer's team; any other pair is
    made on its first ask, hidden and due at once, and a player pair
    untested for longer than the fail-open time turns visible
--]]

function AntiEsp.isHidden(viewer: Viewer, slot: number): boolean
	if not Started then
		error("AntiEsp.isHidden ran before AntiEsp.start", 2)
	end

	local kind: number? = KindOf[slot + 1]
	if kind == nil or kind == NONE then
		-- A value that is no slot is refused by the slot table itself, and a free slot is hidden from no one
		Slots.get(slot)

		return false
	elseif kind == NPC then
		return false
	end

	local generation: number = LifeOf[slot + 1]

	if Ran or viewer ~= Asker then
		attend(viewer)
	end

	local lying: boolean = kind == LYING
	if not lying and AskerTeam ~= nil and teamOf(slot, generation) == AskerTeam then
		return false
	end

	-- The first ask since a slice ran is the relay's next run
	if Ran then
		Round += 1
		Ran = false
	end

	local pair: number = buffer.readu32(AskerTargets, slot * 4)

	if pair == NONE then
		pair = place(AskerIndex, AskerTargets, slot, generation, lying)
	elseif PairLives[pair] ~= generation or PairAsked[pair] < Round - 1 then
		-- A new life starts afresh, as does a pair the relay left out of its last run, which that run dropped
		fresh(pair, generation, lying)
	elseif PairLying[pair] ~= lying then
		rekind(pair, lying)
	end

	PairAsked[pair] = Round

	if PairVerdicts[pair] >= HIDDEN and not lying and Now - PairChecked[pair] > FailOpen then
		PairVerdicts[pair] = FAIL_OPEN
		FailOpens += 1
		schedule(pair, NowQueue, DUE_NOW)
	end

	return PairVerdicts[pair] >= HIDDEN
end

--[[
    Why anti-ESP has a slot sent to a viewer, or held back from it, as the
    relay last asked: an NPC and a player carrying the viewer's team are
    never tested, and any other pair gives its verdict. A pair the relay
    never asked about is untested. It changes nothing, and only a tap asks
--]]

function AntiEsp.reason(key: Key, slot: number): Reason
	if not Started then
		error("AntiEsp.reason ran before AntiEsp.start", 2)
	elseif not Slots.valid(slot) then
		error(`AntiEsp.reason takes one of the slot table's slots, not {slot}`, 2)
	end

	local kind: number = KindOf[slot + 1]
	if kind == NPC then
		return "Npc"
	end

	local index: number? = SightOf[key]
	if index == nil or kind == NONE then
		return "Untested"
	end

	local sight: Sight = Sights[index]
	local generation: number = LifeOf[slot + 1]
	local own: number? = sight.viewer.slot

	if kind == PLAYER and own ~= nil then
		local team: number? = teamOf(own, LifeOf[own + 1])
		if team ~= nil and teamOf(slot, generation) == team then
			return "Teammate"
		end
	end

	local pair: number = buffer.readu32(sight.targets, slot * 4)
	if pair == NONE or PairLives[pair] ~= generation then
		return "Untested"
	end

	return VERDICTS[PairVerdicts[pair]]
end

--[[
    What isHidden would answer if asked now, for a relay worker's stand-in,
    changing no pair: each slot's kind and its life's team, and two rows for
    each viewer in the list, by its place there. A slot's visible bit is set
    when the viewer's pair with it would answer visible on its own verdict,
    and its quiet bit when an ask would only stamp that pair asked, which
    AntiEsp.asked may then do in its place until the next slice. The
    stand-in shows a free slot, an NPC, a player carrying the team of the
    viewer's own slot, and a set visible bit, in that order
--]]

function AntiEsp.answers(viewers: { Viewer }): Answers
	if not Started then
		error("AntiEsp.answers ran before AntiEsp.start", 2)
	elseif type(viewers) ~= "table" then
		error(`AntiEsp.answers takes the relay's viewers as a list, not a {typeof(viewers)}`, 2)
	end

	local kinds: buffer = Answered.kinds
	local teams: buffer = Answered.teams

	for slot: number = 0, SLOTS - 1 do
		buffer.writeu8(kinds, slot, KindOf[slot + 1])
		buffer.writef64(teams, slot * 8, teamOf(slot, LifeOf[slot + 1]) or NO_TEAM)
	end

	-- Rows a viewer, made again only when their count changes
	local size: number = #viewers * ROW_BYTES
	local visible: buffer = Answered.visible
	local quiet: buffer = Answered.quiet
	if buffer.len(visible) ~= size then
		visible = buffer.create(size)
		quiet = buffer.create(size)
		Answered.visible = visible
		Answered.quiet = quiet
	else
		buffer.fill(visible, 0, 0)
		buffer.fill(quiet, 0, 0)
	end

	for index: number, viewer: Viewer in viewers do
		local sight: number? = SightOf[viewer.key]
		if sight ~= nil then
			RowOf[sight] = (index - 1) * ROW_BYTES
		end
	end

	-- The round the asks will be in: the next one once a slice has run since the last
	local round: number = Round
	if Ran then
		round += 1
	end

	AnsweredAt = Slice

	-- A viewer with no pair for a slot yet would make it hidden, so only made pairs can set a bit
	for pair: number = 1, PairTop do
		local row: number? = RowOf[PairSights[pair]]
		if row == nil then
			continue
		end

		local slot: number = PairSlots[pair]
		local kind: number = KindOf[slot + 1]
		if kind ~= PLAYER and kind ~= LYING then
			continue
		end

		local lying: boolean = kind == LYING
		local verdict: number = PairVerdicts[pair]
		local checked: number = PairChecked[pair]
		local kept: boolean = true

		-- As the ask would leave it: afresh for a new life or a pair the relay left out of its last run, and for a
		-- sleep or a wake its verdict kept with its fail-open counted from now
		if PairLives[pair] ~= LifeOf[slot + 1] or PairAsked[pair] < round - 1 then
			verdict = UNTESTED
			checked = Now
			kept = false
		elseif PairLying[pair] ~= lying then
			checked = Now
			kept = false
		end

		local byte: number = row + slot // BITS
		local bit: number = bit32.lshift(1, slot % BITS)
		local failing: boolean = not lying and Now - checked > FailOpen

		if verdict < HIDDEN or failing then
			buffer.writeu8(visible, byte, bit32.bor(buffer.readu8(visible, byte), bit))
		end

		-- Kept as it is and not failing open while hidden, the ask would change nothing but its stamp
		if kept and (verdict < HIDDEN or not failing) then
			buffer.writeu8(quiet, byte, bit32.bor(buffer.readu8(quiet, byte), bit))
		end
	end

	for _, viewer: Viewer in viewers do
		local sight: number? = SightOf[viewer.key]
		if sight ~= nil then
			RowOf[sight] = nil
		end
	end

	return Answered
end

--[[
    Takes a viewer's asks about the first count of slots in isHidden's
    place, each one whose quiet bit the last AntiEsp.answers set: the viewer
    is found and the round opened as an ask does, and each pair is stamped
    asked, which is all those asks would change. A count of 0 changes
    nothing. It refuses a call after a slice since those answers, and a slot
    with no pair an ask would stamp, after stamping the slots before it
--]]

function AntiEsp.asked(viewer: Viewer, slots: { number }, count: number)
	if not Started then
		error("AntiEsp.asked ran before AntiEsp.start", 2)
	elseif AnsweredAt ~= Slice then
		error("AntiEsp.asked ran with no AntiEsp.answers since the last slice, and quiet bits hold only until one", 2)
	elseif count == 0 then
		return
	end

	if Ran or viewer ~= Asker then
		attend(viewer)
	end

	-- The first ask since a slice ran is the relay's next run
	if Ran then
		Round += 1
		Ran = false
	end

	local targets: buffer = AskerTargets
	local round: number = Round

	for index: number = 1, count do
		local slot: number = slots[index]
		local kind: number? = KindOf[slot + 1]
		local pair: number = NONE
		if kind == PLAYER or kind == LYING then
			pair = buffer.readu32(targets, slot * 4)
		end

		if pair == NONE then
			error(`AntiEsp.asked found no pair of the viewer's with slot {slot} that an ask would stamp`, 2)
		end

		PairAsked[pair] = round
	end
end

--[[
    Keeps the pairs of a viewer the relay leaves out of its run, among the
    first count of slots, as that run's asks would have, but for the
    fail-open, which its next ask applies. A free slot, an NPC, a player
    carrying the viewer's team and the viewer's own slot are passed over;
    any other slot opens the round as an ask does, and the viewer's pair
    with it that the round before asked about is stamped asked in this one,
    a new life started afresh and a sleep or wake moved to its new
    schedule, so no slice drops it and its next ask doesn't start it
    afresh. Any older pair stays dropped, and no pair is made. It refuses a
    value that is no slot, after keeping the slots before it
--]]

function AntiEsp.passed(viewer: Viewer, slots: { number }, count: number)
	if not Started then
		error("AntiEsp.passed ran before AntiEsp.start", 2)
	end

	-- A viewer never asked about has no pairs, and its slots are still checked
	local index: number? = SightOf[viewer.key]
	local targets: buffer? = nil
	if index ~= nil then
		local sight: Sight = Sights[index]
		sight.viewer = viewer
		targets = sight.targets
	end

	-- The team of the viewer's own life, as an ask finds it
	local own: number? = viewer.slot
	local team: number? = nil
	if own ~= nil then
		team = teamOf(own, LifeOf[own + 1])
	end

	for at: number = 1, count do
		local slot: number = slots[at]
		local kind: number? = KindOf[slot + 1]
		if kind == nil then
			error(`AntiEsp.passed takes the slot table's slots, not {slot}`, 2)
		end

		local generation: number = LifeOf[slot + 1]
		local lying: boolean = kind == LYING

		-- An ask of these answers without opening a round or stamping a pair, and the relay never asks about the
		-- viewer's own slot
		local mate: boolean = not lying and team ~= nil and teamOf(slot, generation) == team
		if kind == NONE or kind == NPC or slot == own or mate then
			continue
		end

		-- The first ask since a slice ran is the relay's next run, whose first ask of its own then finds its viewer
		-- afresh
		if Ran then
			Round += 1
			Ran = false
			Asker = nil
		end

		local pair: number = NONE
		if targets ~= nil then
			pair = buffer.readu32(targets, slot * 4)
		end

		if pair ~= NONE and PairAsked[pair] == Round - 1 then
			if PairLives[pair] ~= generation then
				fresh(pair, generation, lying)
			elseif PairLying[pair] ~= lying then
				rekind(pair, lying)
			end

			PairAsked[pair] = Round
		end
	end
end

-- Whether two vectors hold the same bits: equal, with each zero's sign the same, which one over it tells apart
local function same(a: vector, b: vector): boolean
	return a == b and 1 / a == 1 / b
end

--[[
    A viewer's rays for this slice: its body's cleared eye, found once a
    tick of the world's and again after its slot changes or moves, and its
    body's move over the look-ahead, its round trip held to the settings'
    clamp, or where it stands with no move while it has no body. With
    verdict memory on, a change to either moves the viewer's stamp on
--]]

local function see(sight: Sight, world: World)
	local viewer: Viewer = sight.viewer
	local own: number? = viewer.slot
	local body: State? = nil
	local changes: number = 0
	if own ~= nil then
		body = Bodies[own]
		changes = ChangesOf[own + 1]
	end

	local lookAhead: number = LookAheadMin
	local connection: Connections.Connection? = Connections.get(viewer.key)
	if connection then
		lookAhead = math.clamp(connection:rtt(), LookAheadMin, LookAheadMax)
	end

	local eye: vector = viewer.position
	local drift: vector = vector.zero

	if body then
		-- A body steps only on the world's ticks, so its eye holds until the next one
		local tick: number = world.clock
		if sight.clearedFor ~= body or sight.clearedTick ~= tick or sight.clearedChanges ~= changes then
			sight.cleared = Eye.clear(body, world)
			sight.clearedFor = body
			sight.clearedTick = tick
			sight.clearedChanges = changes
		end

		eye = sight.cleared
		drift = body.velocity * lookAhead
	end

	if Remembering and not (same(eye, sight.eye) and same(drift, sight.drift)) then
		sight.stamp += 1
	end

	sight.eye = eye
	sight.drift = drift
	sight.lookAhead = lookAhead
	sight.slice = Slice
end

-- Whether any of the first count rays of this test meets no occluder, casting none past the first open one
local function anyOpen(count: number): boolean
	for index: number = 1, count do
		local origin: vector = Origins[index]
		Rays += 1

		if not Blocked(origin, Ends[index] - origin) then
			return true
		end
	end

	return false
end

--[[
    Fills this test's rays from an eye to a player target's aim points for
    its posture, a swimming body taking a crouched one's as its hull does,
    and gives how many. Each ends side studs to the viewer's right of the
    feet raised by up, pushed further out along its side by how far the
    target moves over the look-ahead, and the leading point's ray runs from
    the eye moved by drift to its end moved by the target's velocity
--]]

local function aimRays(eye: vector, drift: vector, lookAhead: number, target: State): number
	local posture: Posture = target.posture
	if posture == "Stand" and target.mode == "Swim" then
		posture = "Crouch"
	end

	local points: Aim = Aims[posture]
	local feet: vector = target.position
	local velocity: vector = target.velocity
	local reach: number = vector.magnitude(velocity) * lookAhead
	local moved: vector = eye + drift

	-- Level across the line to the target, the same to its feet as to its hull's center straight above them
	local x: number = feet.x - eye.x
	local z: number = feet.z - eye.z
	local level: number = math.sqrt(x * x + z * z)

	local right: vector = ACROSS
	if level > 0 then
		right = vector.create(-z / level, 0, x / level)
	end

	for index: number = 1, points.count do
		local side: number = points.sides[index]
		side += math.sign(side) * reach

		local finish: vector =
			vector.create(feet.x + right.x * side, feet.y + points.ups[index], feet.z + right.z * side)
		if points.leads[index] then
			Origins[index] = moved
			Ends[index] = finish + velocity * lookAhead
		else
			Origins[index] = eye
			Ends[index] = finish
		end
	end

	return points.count
end

--[[
    Fills this test's rays from the eye to a sleeper's or body's lying box
    at its lift: its head at the end ahead along its facing, its chest at
    the middle and its feet at the end behind
--]]

local function aimLying(sight: Sight, target: State, settings: Settings)
	local shape: LyingBox = settings.lyingBox
	local eye: vector = sight.eye
	local feet: vector = target.position
	local half: number = shape.length / 2
	local center: vector = vector.create(feet.x, feet.y + shape.lift, feet.z)
	local along: vector = vector.create(-Math.sin(target.facing) * half, 0, -Math.cos(target.facing) * half)

	Origins[1] = eye
	Ends[1] = center + along
	Origins[2] = eye
	Ends[2] = center
	Origins[3] = eye
	Ends[3] = center - along
end

--[[
    Aims one due pair's test: finds its viewer's eye for this slice, takes
    a sleeper's or body's pair out of its group until its test settles, and
    fills the test's rays, giving how many there are
--]]

local function aim(pair: number, world: World): number
	local sight: Sight = Sights[PairSights[pair]]
	if sight.slice ~= Slice then
		see(sight, world)
	end

	local target: State = Bodies[PairSlots[pair]]

	-- Out of its group while its rays are out, so no walk of its viewer's makes it due again in flight
	if PairLying[pair] then
		unlink(pair)
		aimLying(sight, target, world.settings)

		return LyingRays
	end

	return aimRays(sight.eye, sight.drift, sight.lookAhead, target)
end

--[[
    Settles one pair's test from whether a ray was open, on the schedule's
    clock now, and schedules its next. An open ray shows it; every ray
    blocked hides it, unless it was visible and a test found it so inside
    the hold, which keeps it sent until a test after the hold. A sleeper's
    or body's pair joins its viewer's group for this slice
--]]

local function settle(pair: number, open: boolean, now: number)
	local index: number = PairSights[pair]
	local sight: Sight = Sights[index]
	local target: State = Bodies[PairSlots[pair]]
	local lying: boolean = PairLying[pair]
	local hold: number = Hold

	if lying then
		hold = LyingHold
		LyingTests += 1

		join(pair, groupFor(index, sight, now))
	end

	Tests += 1
	PairChecked[pair] = now

	if open then
		PairVerdicts[pair] = CLEAR
		PairSeen[pair] = now

		if lying then
			restamp(pair)
		else
			schedule(pair, VisibleQueue, now + VisibleInterval)
		end
	elseif PairVerdicts[pair] < HIDDEN and now - PairSeen[pair] <= hold then
		PairVerdicts[pair] = HOLD

		-- A sleeper or body held visible is retested once its hold has passed, as often as its rate allows
		if lying then
			heapPush(Timers, pair, restamp(pair), math.max(PairSeen[pair] + hold, now + LyingInterval))
		else
			schedule(pair, VisibleQueue, now + VisibleInterval)
		end
	else
		PairVerdicts[pair] = HIDDEN
		HiddenResults += 1

		-- From the viewer's eye to the target's root, its feet
		local offset: vector = target.position - sight.eye

		if lying then
			restamp(pair)
		elseif vector.dot(offset, offset) <= NearSquared then
			schedule(pair, NearQueue, now + NearInterval)
		else
			schedule(pair, HiddenQueue, now + HiddenInterval)
		end
	end
end

--[[
    Whether a player target stands, bit for bit, as verdict memory's last
    test of its slot saw it, moving the slot's stamp on when its position,
    velocity, posture or swimming differ, and whether its velocity is
    exactly zero, the one case its rays' ends don't read its look-ahead
--]]

local function still(slot: number, target: State): boolean
	local index: number = slot + 1
	local position: vector = target.position
	local velocity: vector = target.velocity
	local posture: Posture = target.posture
	local swimming: boolean = target.mode == "Swim"

	if
		not same(position, Standing.positions[index])
		or not same(velocity, Standing.velocities[index])
		or posture ~= Standing.postures[index]
		or swimming ~= Standing.swims[index]
	then
		Standing.stamps[index] += 1
		Standing.positions[index] = position
		Standing.velocities[index] = velocity
		Standing.postures[index] = posture
		Standing.swims[index] = swimming
	end

	return velocity == vector.zero
end

-- Where a pair's kept box is, the boxes' buffer grown first when it doesn't reach it
local function room(pair: number): number
	local at: number = (pair - 1) * BOX_BYTES
	local boxes: buffer = Kept.boxes

	if at + BOX_BYTES > buffer.len(boxes) then
		local grown: buffer = buffer.create(math.max(at + BOX_BYTES, buffer.len(boxes) * BOX_GROWTH))
		buffer.copy(grown, 0, boxes)
		Kept.boxes = grown
	end

	return at
end

--[[
    Whether any of a player pair's first count rays meets no occluder, as
    anyOpen gives it, with verdict memory on: a ray that crosses the pair's
    kept box counts as blocked with no engine ray, and once every ray is
    blocked, the box of the Block part the first engine ray met is kept, so
    that ray alone asks the occluder what it met
--]]

local function recall(pair: number, count: number): boolean
	local boxed: boolean = Kept.boxEpochs[pair] == Epoch
	local at: number = (pair - 1) * BOX_BYTES
	local first: Met = nil
	local cast: boolean = false

	for index: number = 1, count do
		local origin: vector = Origins[index]
		local finish: vector = Ends[index]

		if boxed and Casts.crosses(Kept.boxes, at, origin, finish) then
			BoxRays += 1
		elseif cast then
			Rays += 1

			if not Blocked(origin, finish - origin) then
				return true
			end
		else
			Rays += 1
			cast = true
			first = Occluder(origin, finish - origin)

			if not first then
				return true
			end
		end
	end

	local part: Part? = nil
	if typeof(first) == "Instance" then
		part = Casts.blocker(first)
	end

	if part then
		local kept: number = room(pair)
		Casts.writeBox(Kept.boxes, kept, part)
		Kept.boxEpochs[pair] = Epoch
	end

	return false
end

--[[
    Holds a test the packing slice answered here, under a new stamp, to land
    beside its batches at the next slice, and whether a kept answer gave it
--]]

local function defer(pair: number, open: boolean, kept: boolean)
	local count: number = Deferred.count + 1
	Deferred.count = count
	Deferred.pairs[count] = pair
	Deferred.stamps[count] = restamp(pair)
	Deferred.opens[count] = open
	Deferred.kept[count] = kept
end

--[[
    Tests one due player pair with verdict memory on, giving whether its
    kept answer settled it. While its viewer's eye and drift, its target
    and the geometry epoch are as when its rays were last aimed, and its
    target has no velocity, that answer settles it with no ray cast or
    packed. Otherwise its rays are aimed, those its kept box blocks counted
    with no engine ray, and the rest cast here or packed for a worker. A
    slice that packs holds what it answers here to land beside its batches,
    as a worker's answer would
--]]

local function remember(pair: number, world: World, now: number): boolean
	local sight: Sight = Sights[PairSights[pair]]
	if sight.slice ~= Slice then
		see(sight, world)
	end

	local slot: number = PairSlots[pair]
	local target: State = Bodies[slot]
	local resting: boolean = still(slot, target)
	local standing: number = Standing.stamps[slot + 1]

	if resting and Kept.epochs[pair] == Epoch and Kept.sights[pair] == sight.stamp and Kept.slots[pair] == standing then
		if Packing then
			local kept: boolean = true -- Counted as a kept test once it lands, as a given-up one never is
			Kept.aimed[pair] = Epoch
			defer(pair, Kept.opens[pair], kept)
		else
			KeptTests += 1
			settle(pair, Kept.opens[pair], now)
		end

		return true
	end

	Kept.sights[pair] = sight.stamp
	Kept.slots[pair] = standing
	Kept.epochs[pair] = NONE
	Kept.aimed[pair] = Epoch

	local count: number = aimRays(sight.eye, sight.drift, sight.lookAhead, target)

	if not Packing then
		local open: boolean = recall(pair, count)
		Kept.epochs[pair] = Epoch
		Kept.opens[pair] = open
		settle(pair, open, now)

		return false
	end

	-- Only the rays the kept box leaves are packed, in their order, so the first open one is still the first
	local boxed: boolean = Kept.boxEpochs[pair] == Epoch
	local at: number = (pair - 1) * BOX_BYTES
	local left: number = 0

	for index: number = 1, count do
		if boxed and Casts.crosses(Kept.boxes, at, Origins[index], Ends[index]) then
			BoxRays += 1
		else
			left += 1
			Origins[left] = Origins[index]
			Ends[left] = Ends[index]
		end
	end

	if left == 0 then
		local open: boolean = false -- Every ray crossed the kept box
		local kept: boolean = false -- Its rays were aimed, so it counts as no kept test
		defer(pair, open, kept)
	else
		local learn: boolean = true -- A player pair's worker sends back the box of the Block part that blocked it
		AntiEspWorkers.add(pair, restamp(pair), left, Origins, Ends, learn)
	end

	return false
end

--[[
    Tests one due pair: casts its rays here, until the first open one, and
    settles it at once, or while the slice packs, packs them for a worker
    under a new stamp, so no entry it waited with can pack it again in flight.
    A player pair goes to verdict memory while it is on, and it gives
    whether a kept answer settled the pair
--]]

local function test(pair: number, world: World, now: number): boolean
	if Remembering and not PairLying[pair] then
		return remember(pair, world, now)
	end

	local count: number = aim(pair, world)

	if Packing then
		AntiEspWorkers.add(pair, restamp(pair), count, Origins, Ends)
	else
		settle(pair, anyOpen(count), now)
	end

	return false
end

--[[
    Takes back one pair a worker tested, counting its rays, and settles it
    on reach, its packing slice's clock plus its lead, so a late result
    stretches neither the hold nor the fail-open. A result whose pair was
    restamped while out is dropped, one with no result is made due again,
    and one whose target is gone or the relay's last run left out is
    released, as the work loop releases one. With verdict memory on, a
    player pair keeps the answer and any box for the epoch it was aimed
    under. It gives whether the result was settled
--]]

local function land(pair: number, stamp: number, open: boolean?, rays: number, reach: number, box: buffer?): boolean
	Rays += rays

	if PairStamps[pair] ~= stamp then
		return false
	elseif open == nil then
		schedule(pair, NowQueue, DUE_NOW)

		return false
	elseif Bodies[PairSlots[pair]] == nil or PairAsked[pair] ~= Round then
		release(pair)

		return false
	end

	if Remembering and not PairLying[pair] then
		Kept.epochs[pair] = Kept.aimed[pair]
		Kept.opens[pair] = open

		if box then
			local kept: number = room(pair)
			buffer.copy(Kept.boxes, kept, box, 0, BOX_BYTES)
			Kept.boxEpochs[pair] = Kept.aimed[pair]
		end
	end

	settle(pair, open, reach)

	return true
end

-- What the workers' collect hands each pair of a landed batch to, which has no use for whether it was settled
local function landBatch(pair: number, stamp: number, open: boolean?, rays: number, reach: number, box: buffer?)
	land(pair, stamp, open, rays, reach, box)
end

--[[
    Lands the tests the last packing slice answered here at its reach, as
    its batches land, unless the slice threw before its send or it was
    longer ago than the fail-open time, when they are made due again. A
    kept answer counts as a kept test only once it is settled
--]]

local function landDeferred(now: number)
	local count: number = Deferred.count
	local late: boolean = now - Deferred.at > FailOpen
	Deferred.count = 0

	for index: number = 1, count do
		local open: boolean? = Deferred.opens[index]
		if index > Deferred.sent or late then
			open = nil
		end

		local settled: boolean = land(Deferred.pairs[index], Deferred.stamps[index], open, 0, Deferred.reach)
		if settled and Deferred.kept[index] then
			KeptTests += 1
		end
	end

	Deferred.sent = 0
end

--[[
    Lets every entry at a queue's front due by now wait in its due heap,
    each one only if it is still its pair's newest. Given a deadline, it
    reads the clock before every DRAIN_CHECK entries and stops at the first
    read that finds the deadline passed, the rest left at the front. It
    gives whether it reached the end of what was due, and whether it took
    any entry
--]]

local function drain(queue: Queue, now: number, deadline: number?): (boolean, boolean)
	local ids: { number } = queue.ids
	local stamps: { number } = queue.stamps
	local times: { number } = queue.times
	local head: number = queue.head
	local tail: number = queue.tail
	local taken: number = 0

	while head <= tail and times[head] <= now do
		if deadline ~= nil and taken % DRAIN_CHECK == 0 and Clock() >= deadline then
			queue.head = head

			return false, taken > 0
		end

		local pair: number = ids[head]
		if PairStamps[pair] == stamps[head] then
			admit(pair)
		end

		head += 1
		taken += 1
	end

	queue.head = head

	return true, taken > 0
end

--[[
    Tests a due heap's pairs lowest key first until the deadline, starting
    none that the slice's mean test of the heap's kind, or of every kind
    while it has none, says would end past it. A test a kept answer settled
    casts nothing, so it stays out of the mean, which a run of them would
    otherwise drag below a test that casts. It first clears the heap of
    stale entries once they outnumber the rest, and gives whether it
    emptied and whether it took any entry. One the relay has stopped asking
    about, or whose target has gone, while it waited is dropped untested
--]]

local function work(heap: Heap, world: World, now: number, deadline: number): (boolean, boolean)
	if heap.stale > heap.count - heap.stale then
		compact(heap)
	end

	local lying: boolean = heap == LyingDue
	local taken: boolean = false

	while heap.count > 0 do
		local clock: number = Clock()
		local run: number = PlayerRun
		local took: number = PlayerTook

		if lying then
			run = LyingRun
			took = LyingTook
		end

		if run == 0 then
			run = LyingRun + PlayerRun
			took = LyingTook + PlayerTook
		end

		-- The slice's first test runs while any time is left, as there is no mean before it
		if clock >= deadline or (run > 0 and clock + took / run > deadline) then
			return false, taken
		end

		local pair: number = heap.ids[1]
		local stamp: number = heap.stamps[1]
		heapPop(heap)
		taken = true

		if PairStamps[pair] ~= stamp then
			heap.stale -= 1
		else
			PairHeaped[pair] = NONE

			if Bodies[PairSlots[pair]] == nil or PairAsked[pair] ~= Round then
				release(pair)
			elseif lying then
				test(pair, world, now)
				LyingRun += 1
				LyingTook += Clock() - clock
			elseif not test(pair, world, now) then
				PlayerRun += 1
				PlayerTook += Clock() - clock
			end
		end
	end

	return true, taken
end

-- The four steps in the order a slice takes them, from its first unless the slice before it was cut
local Steps: { Step } = {
	-- The sleepers' timers reached by due: a held pair's retest, or a group's rate passing while its viewer stays
	-- away. Running whole, the clock is read before each, and the ones the deadline leaves wait at the heap's top,
	-- oldest first
	function (_: World, _: number, due: number, deadline: number, whole: boolean): (boolean, boolean, boolean)
		local took: boolean = false

		while Timers.count > 0 and Timers.keys[1] <= due do
			if whole and Clock() >= deadline then
				return true, took, true
			end

			local id: number = Timers.ids[1]
			local stamp: number = Timers.stamps[1]
			heapPop(Timers)
			took = true

			if id > 0 then
				if PairStamps[id] == stamp then
					admit(id)
				end
			elseif GroupStamps[-id] == stamp and GroupStates[-id] == TIMED then
				local group: number = -id
				local sight: Sight = Sights[GroupSights[group]]
				local walked: vector = sight.viewer.position - GroupFrom[group]

				if vector.dot(walked, walked) > RetestSquared then
					trigger(group)
				else
					GroupStates[group] = WAITING
					sight.dirty = true
				end
			end
		end

		return false, took, false
	end,

	-- Each viewer's walk, measured against its groups only once it may have walked past one. Running whole, the
	-- clock is read before each viewer measured, and the walk goes round Sights from the viewer the last cut stopped
	-- at, a place Sights keeps since it never shrinks, and from the first once a walk ends
	function (_: World, _: number, due: number, deadline: number, whole: boolean): (boolean, boolean, boolean)
		local count: number = #Sights
		local from: number = whole and Whole.walk or 1
		local took: boolean = false

		for step: number = 0, count - 1 do
			local index: number = from + step
			if index > count then
				index -= count
			end

			local sight: Sight = Sights[index]
			if sight.live and sight.groups ~= NONE then
				local position: vector = sight.viewer.position
				local walked: vector = position - sight.anchor

				if sight.dirty or vector.dot(walked, walked) >= sight.margin * sight.margin then
					if whole and Clock() >= deadline then
						Whole.walk = index

						return true, took, true
					end

					took = true
					measure(sight, position, due)
				end
			end
		end

		Whole.walk = 1

		return false, took, false
	end,

	-- Each schedule's front. Running whole, each drain reads the clock every DRAIN_CHECK entries, and the drains start
	-- at the queue the last cut stopped in when it took nothing from it, else at the one after it, so no queue waits on
	-- its place in the order, and at the first once the drains end
	function (_: World, _: number, due: number, deadline: number, whole: boolean): (boolean, boolean, boolean)
		local queues: number = #Queues
		local from: number = whole and Whole.drain or 1
		local stop: number? = nil
		local took: boolean = false

		if whole then
			stop = deadline
		end

		for step: number = 0, queues - 1 do
			local at: number = (from + step - 1) % queues + 1
			local finished: boolean, taken: boolean = drain(Queues[at], due, stop)
			took = took or taken

			if not finished then
				Whole.drain = taken and at % queues + 1 or at

				return true, took, true
			end
		end

		Whole.drain = 1

		return false, took, false
	end,

	-- The tests: sleepers and bodies longest untested first for their share, counted from here and never past the
	-- deadline, then overdue hidden player pairs nearest first and visible ones, then sleepers and bodies again with
	-- whatever the players leave. A slice counts as cut when its deadline came before its tests began, or before their
	-- first test while one waited
	function (world: World, now: number, _: number, deadline: number, _: boolean): (boolean, boolean, boolean)
		LyingRun = 0
		LyingTook = 0
		PlayerRun = 0
		PlayerTook = 0

		local begun: number = Clock()
		local emptied: boolean, took: boolean = work(LyingDue, world, now, math.min(begun + LyingShare, deadline))
		local taken: boolean = false

		-- Whiteoak TODO: a hidden pair waits keyed by its distance when it came due, at most its fail-open time and a
		-- relay interval before it is tested or fails open; keying again by where both stand each slice would order
		-- the wait exactly, once G8 shows the order matters
		emptied, taken = work(HiddenDue, world, now, deadline)
		took = took or taken

		if emptied then
			emptied, taken = work(VisibleDue, world, now, deadline)
			took = took or taken
		end

		if emptied then
			emptied, taken = work(LyingDue, world, now, deadline)
			took = took or taken
		end

		return not emptied, took, begun >= deadline or not (emptied or took)
	end,
}

--[[
    One slice: lets what has come due wait in the due heaps, from the
    sleepers' timers, each viewer's walk and each schedule's front, then
    tests sleepers and bodies longest untested first for their share, then
    overdue hidden player pairs nearest first and visible ones, then
    sleepers and bodies again with whatever the players leave, until budget
    seconds of the clock have passed. Running whole, its timers, walks and
    drains stop at that deadline too, and the next slice goes on from where
    they stopped, beginning at the step the deadline cut. now is the
    schedule's clock every due time is on. With workers it first takes back
    what they landed, and while one is idle packs its tests, up to a relay
    tick ahead, and sends them last, cut or not; with workers on and none
    free it casts here. It is refused inside a hold, whose asks must find
    the verdicts as the round's answers gave them
--]]

function AntiEsp.run(budget: number, now: number)
	local world: World? = Space
	if world == nil then
		error("AntiEsp.run ran before AntiEsp.start", 2)
	elseif Holding then
		error("AntiEsp.run ran inside a hold, which the relay round's release ends", 2)
	elseif type(budget) ~= "number" or not (budget >= 0 and budget < math.huge) then
		error(`AntiEsp.run takes a budget in seconds of 0 or more, not {budget}`, 2)
	elseif type(now) ~= "number" or not (math.abs(now) < math.huge) then
		error(`AntiEsp.run takes the schedule's clock as a finite number, not {now}`, 2)
	end

	local deadline: number = Clock() + budget
	local last: number = Now
	local whole: boolean = Whole.on

	Now = now
	Slice += 1
	Ran = true

	-- 0) What the workers landed since the last slice, settled before anything comes due, while their pool exists,
	-- so a batch out lands after the switch goes off too. With no worker free to take a batch this slice, it casts
	-- here, so it never tests nothing while pairs are due
	Packing = false

	if Pooled then
		local idle: number = AntiEspWorkers.collect(landBatch, now)
		Packing = UseWorkers and idle > 0
		landDeferred(now)
	end

	-- A worker's verdict lands a slice after its rays are packed, so a slice that packs reaches as far ahead as the
	-- last one was behind, at most a relay tick so a stall drains no pair a whole stall early, and the verdict lands
	-- at the slice the pair falls due in, settled on that reach
	local due: number = now
	if Packing and Slice > 1 then
		due += math.min(math.max(now - last, 0), RelayInterval)
	end

	-- 1) to 4) The timers, the walks, the drains and the tests, from the first unless the slice before was cut, when
	-- the slice begins at the step after the one its deadline stopped partway, or at that one when the deadline came
	-- before its first item, and goes round the four from there. The deadline ends the slice at the step it stops
	local steps: number = #Steps
	local first: number = whole and Whole.from or 1
	local cut: boolean = false
	Whole.from = 1

	for offset: number = 0, steps - 1 do
		local at: number = (first + offset - 1) % steps + 1
		local stopped: boolean, took: boolean, counted: boolean = Steps[at](world, now, due, deadline, whole)
		cut = cut or counted

		if stopped then
			if whole then
				Whole.from = took and at % steps + 1 or at
			end

			break
		end
	end

	if cut then
		Whole.cuts += 1
	end

	-- 5) The packed tests, once nothing else in the slice is left to pack, and those answered here go with them
	if Packing then
		Packing = false
		AntiEspWorkers.send(Slice, now, due)

		Deferred.sent = Deferred.count
		Deferred.reach = due
		Deferred.at = now
	end
end

--[[
    Sets whether the slices pack their tests for the Actor workers, from the
    next slice, for a dev bench's before and after on one server. With none
    started, or none free, a slice casts here either way, and batches out
    land whichever it is set to. It starts on when antiEsp.workers is above 0
--]]

function AntiEsp.useWorkers(on: boolean)
	if type(on) ~= "boolean" then
		error(`AntiEsp.useWorkers takes true or false, not {on}`, 2)
	end

	UseWorkers = on
end

-- Whether the slices pack their tests for the Actor workers, as AntiEsp.useWorkers last set it
function AntiEsp.workersOn(): boolean
	return UseWorkers
end

--[[
    Sets whether each slice runs whole, from the next slice: its timers,
    walks and drains stop at its deadline as its tests do, and a slice
    after a cut begins at the step the deadline cut, past it when the cut
    came partway, and goes round all four, the timers oldest first, the
    walk from the viewer it stopped at and the drains from the queue after
    the one cut. Off, as it starts, they run to the end in their order
    whatever the time, reading no clock
--]]

function AntiEsp.useWhole(on: boolean)
	if type(on) ~= "boolean" then
		error(`AntiEsp.useWhole takes true or false, not {on}`, 2)
	end

	Whole.on = on
end

-- Whether each slice runs whole, as AntiEsp.useWhole last set it
function AntiEsp.wholeOn(): boolean
	return Whole.on
end

--[[
    Sets whether verdict memory runs, for a dev bench's before and after:
    a player pair's last answer kept while nothing its rays are aimed from
    has moved, no occluder joined or left the include list and no listed
    instance moved, and the box of the Block part that last blocked it
    tested first. An occluder changed in place, or terrain written, goes
    unseen but through occludersChanged, so it is no game's setting. On, it
    drops what it kept and listens to the list; off, it stops listening. It
    is refused before start
--]]

function AntiEsp.useMemory(on: boolean)
	if not Started then
		error("AntiEsp.useMemory ran before AntiEsp.start", 2)
	elseif type(on) ~= "boolean" then
		error(`AntiEsp.useMemory takes true or false, not {on}`, 2)
	end

	-- The switch owns these: each goes in Watching, which useMemory(false) disconnects and empties
	if on and not Remembering then
		for _, instance: Instance in Include do
			table.insert(Watching, instance.DescendantAdded:Connect(shift))
			table.insert(Watching, instance.DescendantRemoving:Connect(shift))
			table.insert(Watching, instance.AncestryChanged:Connect(shift))
		end
	elseif not on then
		for _, connection: RBXScriptConnection in Watching do
			connection:Disconnect()
		end

		table.clear(Watching)
	end

	if on then
		shift()
	end

	Remembering = on
end

-- Whether verdict memory runs, as AntiEsp.useMemory last set it
function AntiEsp.memoryOn(): boolean
	return Remembering
end

--[[
    Tells verdict memory the occluders changed in place, one moved, resized
    or made unqueryable, or terrain written, which the include list's own
    events don't show, so it uses no answer or box it kept before
--]]

function AntiEsp.occludersChanged()
	shift()
end

--[[
    The tests a kept answer settled and the rays a kept box blocked with no
    engine ray cast, each since start, changing nothing, so each dev bench
    reading them takes the difference between two of its own reads
--]]

function AntiEsp.memory(): (number, number)
	return KeptTests, BoxRays
end

-- Gives a slot's life of a generation a team, nil for none
local function giveTeam(slot: number, team: number?, generation: number)
	-- The next ask finds its viewer's team afresh
	Asker = nil

	if team == nil then
		buffer.writeu8(TeamLives, slot, 0)

		return
	end

	buffer.writef64(TeamValues, slot * 8, team)
	buffer.writeu8(TeamLives, slot, generation + 1)
end

--[[
    Gives a slot's current life a team, nil for none. Two players carrying
    the same team are never hidden from each other, and a new life of the
    slot starts with none. Inside a hold it runs at the release, for the
    life the slot had at the call
--]]

function AntiEsp.setTeam(slot: number, team: number?)
	if not Started then
		error("AntiEsp.setTeam ran before AntiEsp.start", 2)
	elseif not Slots.valid(slot) then
		error(`AntiEsp.setTeam takes one of the slot table's slots, not {slot}`, 2)
	elseif team ~= nil and (type(team) ~= "number" or team ~= team) then
		error(`AntiEsp.setTeam takes a team as a number or nil, not {team}`, 2)
	end

	local generation: number = Slots.get(slot)

	if Holding then
		table.insert(Held, function ()
			giveTeam(slot, team, generation)
		end)
	else
		giveTeam(slot, team, generation)
	end
end

-- Makes every pair a slot is in due now, and finds its own viewer's eye again
local function due(slot: number)
	for _, sight: Sight in Sights do
		if not sight.live then
			continue
		end

		local targets: buffer = sight.targets
		local pair: number = buffer.readu32(targets, slot * 4)
		if pair ~= NONE then
			schedule(pair, NowQueue, DUE_NOW)
		end

		if sight.viewer.slot == slot then
			sight.clearedFor = nil

			for target: number = 0, SLOTS - 1 do
				local own: number = buffer.readu32(targets, target * 4)
				if own ~= NONE then
					schedule(own, NowQueue, DUE_NOW)
				end
			end
		end
	end
end

--[[
    Makes every pair a slot is in due now, as each viewer's target and as
    the viewer whose own character it is, whose kept eye is found again,
    for a teleport's landing or a sleeper's move. Inside a hold it runs at
    the release
--]]

function AntiEsp.moved(slot: number)
	if not Started then
		error("AntiEsp.moved ran before AntiEsp.start", 2)
	elseif not Slots.valid(slot) then
		error(`AntiEsp.moved takes one of the slot table's slots, not {slot}`, 2)
	end

	if Holding then
		table.insert(Held, function ()
			due(slot)
		end)
	else
		due(slot)
	end
end

-- Forgets a viewer and every pair it held, if anti-ESP was ever asked about it
local function forget(key: Key)
	local index: number? = SightOf[key]
	if index == nil then
		return
	end

	local sight: Sight = Sights[index]
	for target: number = 0, SLOTS - 1 do
		local pair: number = buffer.readu32(sight.targets, target * 4)
		if pair ~= NONE then
			release(pair)
		end
	end

	Asker = nil
	sight.live = false
	SightOf[key] = nil
	table.insert(FreeSights, index)
end

--[[
    Forgets a viewer that left and every pair it held. One anti-ESP was
    never asked about leaves nothing to forget. Inside a hold it runs at the
    release, so the round's asks about the viewer are forgotten with it
--]]

function AntiEsp.leave(key: Key)
	if not Started then
		error("AntiEsp.leave ran before AntiEsp.start", 2)
	elseif key == nil then
		error("AntiEsp.leave takes the player or bot that left, not nil", 2)
	end

	if Holding then
		table.insert(Held, function ()
			forget(key)
		end)
	else
		forget(key)
	end
end

--[[
    Holds every change to anti-ESP's state while a relay round is out, the
    game's, the server's and the slot table's, until AntiEsp.release. Asks
    still run inside it, and a slice is refused
--]]

function AntiEsp.hold()
	if not Started then
		error("AntiEsp.hold ran before AntiEsp.start", 2)
	elseif Holding then
		error("AntiEsp.hold ran while its last hold was still out", 2)
	end

	Holding = true
end

--[[
    Ends the hold, making each change held since it in the order it came,
    as each would have run once the round's asks were done
--]]

function AntiEsp.release()
	if not Holding then
		error("AntiEsp.release ran with no hold out", 2)
	end

	Holding = false

	for _, change: () -> () in Held do
		change()
	end

	table.clear(Held)
end

--[[
    The pair tests run, the tests that left their pair hidden, and the
    player pairs that failed open, each since start, for the server's stats
--]]

function AntiEsp.counts(): (number, number, number)
	return Tests, HiddenResults, FailOpens
end

--[[
    The slices the deadline cut short, since start, for the server's stats:
    every slice whose deadline had passed when its tests began or before
    their first test, which with the slice not running whole is one whose
    worker landing, timers, walks and drains ran past its deadline, and,
    running whole, every slice whose timers, walks or drains its deadline
    stopped. A slice whose tests stop at its deadline after their first,
    as a busy one's do, isn't one
--]]

function AntiEsp.cuts(): number
	return Whole.cuts
end

--[[
    The sleepers' and bodies' pair tests run since the last call, and their
    pairs due and waiting untested in the slices' heap now, which a slice
    short of time leaves there and never fails open, for the server's stats
--]]

function AntiEsp.lying(): (number, number)
	local tests: number = LyingTests
	LyingTests = 0

	return tests, LyingDue.count - LyingDue.stale
end

--[[
    The rays cast on the engine since the last call, the server's own and
    those of the workers' batches that landed, for the server's stats
--]]

function AntiEsp.rays(): number
	local rays: number = Rays
	Rays = 0

	return rays
end

--[[
    Writes the points a player pair's rays from an eye aim at on a target,
    for its posture with no look-ahead, into into's first entries, and
    gives how many it wrote
--]]

function AntiEsp.aimPoints(eye: vector, target: State, into: { vector }): number
	if not Started then
		error("AntiEsp.aimPoints ran before AntiEsp.start", 2)
	end

	local count: number = aimRays(eye, vector.zero, 0, target)
	for index: number = 1, count do
		into[index] = Ends[index]
	end

	return count
end

return AntiEsp
