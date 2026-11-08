--[[
    Anti-ESP's serial job: which characters each viewer may be sent, tested
    with rays from its cleared eye on the schedules the server settings
    give, a slice at a time inside a budget
--]]

--!strict
--!native
local Config = require(script.Parent.Parent.Config)
local Connections = require(script.Parent.Connections)
local Constants = require(script.Parent.Parent.Constants)
local Eye = require(script.Parent.Parent.Step.Eye)
local Hulls = require(script.Parent.Parent.Step.Hulls)
local Math = require(script.Parent.Parent.Step.Math)
local Relay = require(script.Parent.Relay)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)

local SLOTS: number = Constants.SLOTS
local PLAYER_RAYS: number = Constants.PLAYER_RAYS -- The rays a player pair's test has
local LYING_RAYS: number = Constants.LYING_RAYS -- A sleeper's or body's
local NONE: number = 0 -- No pair, group, kind or heap, in every index and link
local DUE_NOW: number = -math.huge -- A due time every slice has reached
local ACROSS: vector = vector.create(1, 0, 0) -- The side rays' axis toward a target straight above or below the eye

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

type Bot = { Name: string }
type Entry = Slots.Entry
type Key = Player | Bot
type LyingBox = State.LyingBox
type ServerSettings = Config.ServerSettings
type Settings = State.Settings
type Shared = Config.Shared
type State = State.State
type Viewer = Relay.Viewer
type World = State.World

-- What anti-ESP keeps for one viewer, made at its first pair and reused for another once it leaves
type Sight = {
	viewer: Viewer, -- The table the relay last asked with, which the server handle refills each relay tick
	live: boolean, -- False once it leaves, until another viewer takes its place
	targets: buffer, -- u32: its pair with each slot, NONE for none
	slice: number, -- The slice its eye was last found in
	eye: vector, -- Where its rays start this slice: its cleared eye, or where it stands while it has no body
	drift: vector, -- How far its body moves over the look-ahead
	lookAhead: number, -- Its round trip held to the settings' clamp, in seconds
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

local Started: boolean = false

-- What start hands in
local Space: World? = nil -- The server's world, whose casts clear each viewer's eye
local Bodies: { [number]: State } = {} -- The server's states by slot, read where they stand at each test

-- Whiteoak TODO: a custom terrain route's heightfield joins these rays through the game's cast wrapper once that
-- route exists; until then they meet only what blocked casts against
local Blocked: (origin: vector, direction: vector) -> boolean = function (_: vector, _: vector): boolean
	error("AntiEsp casts no ray until AntiEsp.start hands it blocked")
end

-- The server settings as the slices read them, each rate as the seconds between tests
local PlayerRays: number = 0
local LyingRays: number = 0
local LookAheadMin: number = 0
local LookAheadMax: number = 0
local HiddenInterval: number = 0
local VisibleInterval: number = 0
local Hold: number = 0
local FailOpen: number = 0
local Retest: number = 0
local RetestSquared: number = 0
local LyingInterval: number = 0
local LyingHold: number = 0

local Now: number = 0 -- The schedule's clock at the last slice, which an ask's fail-open is measured on
local Slice: number = 0 -- The slices run since start
local Round: number = 0 -- The relay's runs that asked about a pair
local Ran: boolean = true -- Whether a slice ran since the relay last asked, so its next ask starts a round

-- Since start, for the server's stats
local Tests: number = 0
local HiddenResults: number = 0 -- Tests that left their pair hidden
local FailOpens: number = 0

-- Each slot's kind and generation by its slot plus 1, kept from the slot table's changes, so an ask calls nothing
local KindOf: { number } = table.create(SLOTS, NONE)
local LifeOf: { number } = table.create(SLOTS, 0)

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

-- Every pair by its index, each field an array, and the indexes a dropped pair left free
local PairSights: { number } = {} -- Its viewer's place in Sights, NONE while free
local PairSlots: { number } = {} -- Its target's slot
local PairLives: { number } = {} -- And the target's generation
local PairLying: { boolean } = {} -- A sleeper or body, on the sleepers' schedule
local PairHidden: { boolean } = {}
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

-- The schedules whose due times come in the order they are set, as the schedule's clock never runs back
local NowQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local HiddenQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }
local VisibleQueue: Queue = { ids = {}, stamps = {}, times = {}, head = 1, tail = 0 }

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
end

--[[
    Starts anti-ESP with the game's checked tables, the server's world for
    each viewer's cleared eye, the states the server keeps by slot, and
    blocked, true when a ray from origin along direction meets an occluder.
    It refuses more rays than a pair's test has, and runs once
--]]

function AntiEsp.start(
	settings: { shared: Shared, server: ServerSettings },
	world: World,
	states: { [number]: State },
	blocked: (origin: vector, direction: vector) -> boolean
)
	if Started then
		error("AntiEsp.start runs once, and it has already run", 2)
	elseif type(settings) ~= "table" or type(world) ~= "table" or type(states) ~= "table" then
		error("AntiEsp.start takes the settings, the server's world and its states as tables", 2)
	elseif type(blocked) ~= "function" then
		error(`AntiEsp.start takes blocked as a function, not a {typeof(blocked)}`, 2)
	end

	local server: ServerSettings = settings.server
	local rays: number = server.antiEsp.rays
	local lyingRays: number = server.sleepers.rays

	if rays > PLAYER_RAYS then
		error(`server.antiEsp.rays is at most the {PLAYER_RAYS} rays a player pair's test has, not {rays}`, 2)
	elseif lyingRays > LYING_RAYS then
		error(`server.sleepers.rays is at most the {LYING_RAYS} rays a sleeper's test has, not {lyingRays}`, 2)
	end

	Started = true
	Space = world
	Bodies = states
	Blocked = blocked

	PlayerRays = rays
	LyingRays = lyingRays
	LookAheadMin = server.antiEsp.lookAheadMin
	LookAheadMax = server.antiEsp.lookAheadMax
	HiddenInterval = 1 / server.antiEsp.hiddenRate
	VisibleInterval = 1 / server.antiEsp.visibleRate
	Hold = server.antiEsp.hold
	FailOpen = server.antiEsp.failOpen
	Retest = server.sleepers.retest
	RetestSquared = Retest ^ 2
	LyingInterval = 1 / server.sleepers.rate
	LyingHold = server.sleepers.hold

	for slot: number = 0, SLOTS - 1 do
		local generation: number, entry: Entry? = Slots.get(slot)
		note(slot, generation, entry)
	end

	-- Lives as long as the server, as anti-ESP does
	Slots.onChange(function (slot: number, generation: number, _: Entry?, current: Entry?)
		note(slot, generation, current)
	end)
end

--[[
    Adds an entry behind a queue's others, first moving what is left to the
    front once the entries taken outnumber it, so its arrays never grow far
    past the most it has held
--]]

local function enqueue(queue: Queue, id: number, stamp: number, time: number)
	local head: number = queue.head
	local tail: number = queue.tail
	local left: number = tail - head + 1

	if head > 1 and head - 1 >= left then
		table.move(queue.ids, head, tail, 1)
		table.move(queue.stamps, head, tail, 1)
		table.move(queue.times, head, tail, 1)
		queue.head = 1
		tail = left
	end

	tail += 1
	queue.ids[tail] = id
	queue.stamps[tail] = stamp
	queue.times[tail] = time
	queue.tail = tail
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
	elseif PairHidden[pair] then
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
			lookAhead = 0,
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
    its place, its pairs by slot and its own character's team
--]]

local function attend(viewer: Viewer)
	local index: number, sight: Sight = sightOf(viewer)
	local own: number? = viewer.slot

	AskerTeam = nil
	if own ~= nil then
		local ownGeneration: number = Slots.get(own)
		AskerTeam = teamOf(own, ownGeneration)
	end

	Asker = viewer
	AskerIndex = index
	AskerTargets = sight.targets
end

-- A pair as each life starts it: hidden, never seen and due at once, its fail-open counted from now
local function fresh(pair: number, generation: number, lying: boolean)
	unlink(pair)

	PairLives[pair] = generation
	PairLying[pair] = lying
	PairHidden[pair] = true
	PairChecked[pair] = Now
	PairSeen[pair] = -math.huge

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
		-- A character falling asleep or waking keeps its life and its verdict, retested on its new schedule, so a
		-- sleeper long untested that wakes doesn't fail open before its first test as a player
		PairLying[pair] = lying
		PairChecked[pair] = Now

		if not lying then
			unlink(pair)
		end

		schedule(pair, NowQueue, DUE_NOW)
	end

	PairAsked[pair] = Round

	if PairHidden[pair] and not lying and Now - PairChecked[pair] > FailOpen then
		PairHidden[pair] = false
		FailOpens += 1
		schedule(pair, NowQueue, DUE_NOW)
	end

	return PairHidden[pair]
end

--[[
    A viewer's rays for this slice: its body's cleared eye, and its body's
    move over the look-ahead, its round trip held to the settings' clamp,
    or where it stands with no move while it has no body
--]]

local function see(sight: Sight, world: World)
	local viewer: Viewer = sight.viewer
	local own: number? = viewer.slot
	local body: State? = nil
	if own ~= nil then
		body = Bodies[own]
	end

	local lookAhead: number = LookAheadMin
	local connection: Connections.Connection? = Connections.get(viewer.key)
	if connection then
		lookAhead = math.clamp(connection:rtt(), LookAheadMin, LookAheadMax)
	end

	if body then
		sight.eye = Eye.clear(body, world)
		sight.drift = body.velocity * lookAhead
	else
		sight.eye = viewer.position
		sight.drift = vector.zero
	end

	sight.lookAhead = lookAhead
	sight.slice = Slice
end

-- Whether any of the first count rays of this test meets no occluder, casting none past the first open one
local function anyOpen(count: number): boolean
	for index: number = 1, count do
		local origin: vector = Origins[index]
		if not Blocked(origin, Ends[index] - origin) then
			return true
		end
	end

	return false
end

--[[
    A player pair's rays from the eye: to the target's head and its hull's
    center, to that center pushed either way across the line by the hull
    radius and how far the target moves over the look-ahead, and from the
    eye moved by the viewer's velocity to the center moved by the target's
--]]

local function playerOpen(sight: Sight, target: State, settings: Settings): boolean
	local eye: vector = sight.eye
	local lookAhead: number = sight.lookAhead
	local feet: vector = target.position
	local center: vector = vector.create(feet.x, feet.y + Hulls.height(target, settings) / 2, feet.z)
	local toward: vector = center - eye
	local level: number = math.sqrt(toward.x * toward.x + toward.z * toward.z)

	local across: vector = ACROSS
	if level > 0 then
		across = vector.create(toward.z / level, 0, -toward.x / level)
	end

	local push: vector = across * (settings.radius + vector.magnitude(target.velocity) * lookAhead)
	local moved: vector = eye + sight.drift

	Origins[1] = eye
	Ends[1] = vector.create(feet.x, feet.y + target.eyeHeight, feet.z)
	Origins[2] = eye
	Ends[2] = center
	Origins[3] = eye
	Ends[3] = center + push
	Origins[4] = eye
	Ends[4] = center - push
	Origins[5] = moved
	Ends[5] = center + target.velocity * lookAhead

	return anyOpen(PlayerRays)
end

--[[
    A sleeper's or body's rays from the eye to its lying box at its lift:
    its head at the end ahead along its facing, its chest at the middle and
    its feet at the end behind
--]]

local function lyingOpen(sight: Sight, target: State, settings: Settings): boolean
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

	return anyOpen(LyingRays)
end

--[[
    Tests one due pair and schedules its next test. An open ray shows it;
    every ray blocked hides it, unless it was visible and a test found it so
    inside the hold, which keeps it sent until a test after the hold. A
    sleeper's or body's pair joins its viewer's group for this slice
--]]

local function test(pair: number, world: World, now: number)
	local index: number = PairSights[pair]
	local sight: Sight = Sights[index]
	if sight.slice ~= Slice then
		see(sight, world)
	end

	local target: State = Bodies[PairSlots[pair]]
	local lying: boolean = PairLying[pair]
	local open: boolean
	local hold: number = Hold

	if lying then
		open = lyingOpen(sight, target, world.settings)
		hold = LyingHold

		unlink(pair)
		join(pair, groupFor(index, sight, now))
	else
		open = playerOpen(sight, target, world.settings)
	end

	Tests += 1
	PairChecked[pair] = now

	if open then
		PairHidden[pair] = false
		PairSeen[pair] = now

		if lying then
			restamp(pair)
		else
			schedule(pair, VisibleQueue, now + VisibleInterval)
		end
	elseif not PairHidden[pair] and now - PairSeen[pair] <= hold then
		-- A sleeper or body held visible is retested once its hold has passed, as often as its rate allows
		if lying then
			heapPush(Timers, pair, restamp(pair), math.max(PairSeen[pair] + hold, now + LyingInterval))
		else
			schedule(pair, VisibleQueue, now + VisibleInterval)
		end
	else
		PairHidden[pair] = true
		HiddenResults += 1

		if lying then
			restamp(pair)
		else
			schedule(pair, HiddenQueue, now + HiddenInterval)
		end
	end
end

-- Lets every entry at a queue's front due by now wait in its due heap, each one only if it is still its pair's newest
local function drain(queue: Queue, now: number)
	local ids: { number } = queue.ids
	local stamps: { number } = queue.stamps
	local times: { number } = queue.times
	local head: number = queue.head
	local tail: number = queue.tail

	while head <= tail and times[head] <= now do
		local pair: number = ids[head]
		if PairStamps[pair] == stamps[head] then
			admit(pair)
		end

		head += 1
	end

	queue.head = head
end

--[[
    Tests a due heap's pairs lowest key first while the slice's time lasts,
    first clearing it of stale entries once they outnumber the rest, and
    whether it emptied. One the relay has stopped asking about, or whose
    target has gone, while it waited is dropped untested
--]]

local function work(heap: Heap, world: World, now: number, deadline: number): boolean
	if heap.stale > heap.count - heap.stale then
		compact(heap)
	end

	while heap.count > 0 do
		if os.clock() >= deadline then
			return false
		end

		local pair: number = heap.ids[1]
		local stamp: number = heap.stamps[1]
		heapPop(heap)

		if PairStamps[pair] ~= stamp then
			heap.stale -= 1
		else
			PairHeaped[pair] = NONE

			if Bodies[PairSlots[pair]] == nil or PairAsked[pair] ~= Round then
				release(pair)
			else
				test(pair, world, now)
			end
		end
	end

	return true
end

--[[
    One slice: lets what has come due wait in the due heaps, from the
    sleepers' timers, each viewer's walk and each schedule's front, then
    tests overdue hidden player pairs nearest first, visible ones and then
    sleepers and bodies longest untested first, until budget seconds of
    os.clock() have passed. now is the schedule's clock every due time is on
--]]

function AntiEsp.run(budget: number, now: number)
	local world: World? = Space
	if world == nil then
		error("AntiEsp.run ran before AntiEsp.start", 2)
	elseif type(budget) ~= "number" or not (budget >= 0 and budget < math.huge) then
		error(`AntiEsp.run takes a budget in seconds of 0 or more, not {budget}`, 2)
	elseif type(now) ~= "number" or not (math.abs(now) < math.huge) then
		error(`AntiEsp.run takes the schedule's clock as a finite number, not {now}`, 2)
	end

	-- Whiteoak TODO: a catch-up Heartbeat that runs the stage twice spends two slices in that frame; the tick handing
	-- run its Heartbeat's number would let a second call in one frame spend nothing, once G3 shows the cost
	local deadline: number = os.clock() + budget

	Now = now
	Slice += 1
	Ran = true

	-- 1) The sleepers' timers reached: a held pair's retest, or a group's rate passing while its viewer stays away
	while Timers.count > 0 and Timers.keys[1] <= now do
		local id: number = Timers.ids[1]
		local stamp: number = Timers.stamps[1]
		heapPop(Timers)

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

	-- 2) Each viewer's walk, measured against its groups only once it may have walked past one
	for _, sight: Sight in Sights do
		if sight.live and sight.groups ~= NONE then
			local position: vector = sight.viewer.position
			local walked: vector = position - sight.anchor

			if sight.dirty or vector.dot(walked, walked) >= sight.margin * sight.margin then
				measure(sight, position, now)
			end
		end
	end

	-- 3) Each schedule's front
	drain(NowQueue, now)
	drain(HiddenQueue, now)
	drain(VisibleQueue, now)

	-- Whiteoak TODO: a hidden pair waits keyed by its distance when it came due, at most its fail-open time and a
	-- relay interval before it is tested or fails open; keying again by where both stand each slice would order the
	-- wait exactly, once G8 shows the order matters
	if work(HiddenDue, world, now, deadline) and work(VisibleDue, world, now, deadline) then
		work(LyingDue, world, now, deadline)
	end
end

--[[
    Gives a slot's current life a team, nil for none. Two players carrying
    the same team are never hidden from each other, and a new life of the
    slot starts with none
--]]

function AntiEsp.setTeam(slot: number, team: number?)
	if not Started then
		error("AntiEsp.setTeam ran before AntiEsp.start", 2)
	elseif not Slots.valid(slot) then
		error(`AntiEsp.setTeam takes one of the slot table's slots, not {slot}`, 2)
	elseif team ~= nil and (type(team) ~= "number" or team ~= team) then
		error(`AntiEsp.setTeam takes a team as a number or nil, not {team}`, 2)
	end

	-- The next ask finds its viewer's team afresh
	Asker = nil

	if team == nil then
		buffer.writeu8(TeamLives, slot, 0)

		return
	end

	local generation: number = Slots.get(slot)
	buffer.writef64(TeamValues, slot * 8, team)
	buffer.writeu8(TeamLives, slot, generation + 1)
end

--[[
    Makes every pair a slot is in due now, as each viewer's target and as
    the viewer whose own character it is, for a teleport's landing or a
    sleeper's move
--]]

function AntiEsp.moved(slot: number)
	if not Started then
		error("AntiEsp.moved ran before AntiEsp.start", 2)
	elseif not Slots.valid(slot) then
		error(`AntiEsp.moved takes one of the slot table's slots, not {slot}`, 2)
	end

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
    Forgets a viewer that left and every pair it held. One anti-ESP was
    never asked about leaves nothing to forget
--]]

function AntiEsp.leave(key: Key)
	if not Started then
		error("AntiEsp.leave ran before AntiEsp.start", 2)
	elseif key == nil then
		error("AntiEsp.leave takes the player or bot that left, not nil", 2)
	end

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
    The pair tests run, the tests that left their pair hidden, and the
    player pairs that failed open, each since start, for the server's stats
--]]

function AntiEsp.counts(): (number, number, number)
	return Tests, HiddenResults, FailOpens
end

return AntiEsp
