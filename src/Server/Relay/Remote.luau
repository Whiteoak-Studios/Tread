--[[
    A relay worker's side of each run, in an Actor's VM: the hand-ins read
    into its own world and views, the calls queued for them, the watches and
    turns of the viewers it is handed, and the result that carries them back
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Parent.Codec.Block)
local Constants = require(script.Parent.Parent.Parent.Constants)
local Slots = require(script.Parent.Parent.Slots)
local Turn = require(script.Parent.Turn)
local Wire = require(script.Parent.Wire)

local SLOTS: number = Constants.SLOTS
local MAX_WATCHERS: number = Constants.MAX_WATCHERS
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row
local ROW_BYTES: number = Wire.ROW_BYTES -- A viewer's visible row, its quiet row right behind it

-- Anti-ESP's kinds as AntiEsp.answers gives them, which its stand-in reads
local FREE: number = 0
local PLAYER: number = 1
local NPC: number = 3

type Bot = { Name: string }
type Copy = Wire.Copy
type Hand = Wire.Hand
type Key = Player | Bot
type Settings = Turn.Settings
type Shared = Wire.Shared
type View = Turn.View
type Viewer = Turn.Viewer

local World: Turn.World = Turn.world
local Changes: boolean = false -- Whether records go as changes, as the settings say

-- Each key's handle by its id, which Turn keeps the key's view under, and each handle's id
local Handles: { [number]: Key } = {}
local Ids: { [Key]: number } = {}
local Nobody: Bot = { Name = "" } -- What a viewer table holds before its first viewer is read into it

-- What this worker last told the front of each view it ran, by its handle, the copy the front keeps of it
local Shadows: { [Key]: Copy } = {}

-- The handles a removal let go this run, kept through the run's sweep so one handed in again keeps the watcher bits
-- its targets' views hold for it, as the front's own Turn keeps them by key
local Leaving: { [Key]: boolean } = {}

-- The shared hand-in's header, bands and marks, with anti-ESP's kind and team by slot for this run's bodies
local Header: Shared = {
	run = 0,
	tick = 0,
	elapsed = 0,
	wire = 0,
	tune = Wire.tuning(),
	places = 0,
	looks = {},
	lookCount = 0,
	helds = {},
	heldCount = 0,
	observing = false,
	observed = {},
	observedCount = 0,
	kinds = buffer.create(SLOTS),
	teams = buffer.create(SLOTS * 8),
}
local AntiKinds: buffer = Header.kinds
local AntiTeams: buffer = Header.teams

local Places: buffer = buffer.create(SLOTS * 2) -- u16 by slot: its place from 1 in this run's walk
local Observed: { [Key]: boolean } = {} -- The handles whose blocks a sink observes
local Observing: boolean = false

-- The viewers handed in, each hand and viewer table kept for its place in the list and reused run to run
local Hands: { Hand } = {}
local Pool: { Viewer } = {}
local List: { Viewer } = {}

local Writer: Wire.Writer = Wire.writer()
local Own: buffer = buffer.create(0) -- This run's own hand-in, whose rows the stand-in for anti-ESP reads
local Recipients: { number } = {} -- The ids of the turn's recipients

-- The turn being taken: its viewer's visible row in Own, its quiet row behind it, its own team, its traffic, and
-- whether a sink observes any of its recipients
local TurnRow: number = 0
local TurnTeam: number = 0
local TurnTraffic: number = 0
local TurnObserved: boolean = false

-- Turn's running totals as the last result counted them
local Sent: number = 0
local Cut: number = 0
local Visited: number = 0
local Rest: number = 0

-- With relay.clocks on, each run's clocks, laid out as Wire.CLOCKS names them and made at setup, and when the part of
-- the run being timed began
local Clock: { on: boolean, laps: buffer, from: number } = { on = false, laps = buffer.create(0), from = 0 }
local AT: { [string]: number } = Wire.CLOCK_AT -- Each section's offset in the clocks

local Remote = {}

-- The handle Turn keeps an id's view under, made the first time the id is handed in
local function handle(id: number): Key
	local kept: Key? = Handles[id]
	if kept then
		return kept
	end

	local made: Bot = { Name = `{id}` }
	Handles[id] = made
	Ids[made] = id

	return made
end

-- Forgets a removed viewer's handle, so an id handed in after it makes a new one
local function forget(id: number)
	local kept: Key? = Handles[id]
	if kept then
		Handles[id] = nil
		Ids[kept] = nil
		Shadows[kept] = nil
	end
end

-- The viewer table kept for a place in the list, made the first time the list is that long
local function viewerAt(index: number): Viewer
	local kept: Viewer? = Pool[index]
	if kept then
		return kept
	end

	local made: Viewer = {
		key = Nobody,
		slot = nil,
		position = vector.zero,
		acknowledged = 0,
		received = 0,
		target = nil,
		look = nil,
		zoomed = false,
		delay = 0,
	}
	Pool[index] = made

	return made
end

-- The shadow of what the front holds of a handle's view, made empty the first time the view runs here
local function shadowOf(key: Key): Copy
	local kept: Copy? = Shadows[key]
	if kept then
		return kept
	end

	local made: Copy = Wire.copy()
	Shadows[key] = made

	return made
end

-- The ports a turn calls out through, each writing into the result or answering from the hand-ins
local function send(_: { Key }, data: buffer)
	Wire.send(Writer, data)
end

local function sendWithheld(_: { Key }, data: buffer)
	Wire.withheld(Writer, data)
end

local function heard(_: { Key }, _: number, sequence: number)
	Wire.heard(Writer, sequence)
end

local function traffic(_: Key): number
	return TurnTraffic
end

--[[
    Anti-ESP's stand-in, from the answers the front exported for this run:
    a free slot and an NPC visible, a player carrying the team of the
    viewer's own slot visible, a slot whose bit is set visible, and any
    other hidden. Each ask is kept at its walk place for the front's replay,
    as a mark where its quiet bit is set, the first three always as asks
--]]

local function isHidden(_: Viewer, slot: number): boolean
	local place: number = buffer.readu16(Places, slot * 2)
	local kind: number = buffer.readu8(AntiKinds, slot)

	-- The quiet bit ignores teams, and a teammate's ask can make its viewer's record, so it goes as an ask
	if kind == FREE or kind == NPC or (kind == PLAYER and buffer.readf64(AntiTeams, slot * 8) == TurnTeam) then
		Wire.ask(Writer, place)

		return false
	end

	local at: number = TurnRow + slot // BITS
	local bit: number = bit32.lshift(1, slot % BITS)
	if bit32.btest(buffer.readu8(Own, at + ROW_BYTES), bit) then
		Wire.mark(Writer, place)
	else
		Wire.ask(Writer, place)
	end

	return not bit32.btest(buffer.readu8(Own, at), bit)
end

local function observing(): boolean
	return Observing
end

local function observes(keys: { Key }, count: number): boolean
	for index: number = 1, count do
		if Observed[keys[index]] then
			return true
		end
	end

	return false
end

-- A tap on a block whose recipients no sink observes is the plain block just sent, so only an observed one carries
-- the bytes it was handed
local function relayed(_: { Key }, _: number, block: Block.Block, data: buffer)
	if TurnObserved then
		Wire.relayed(Writer, block, data)
	else
		Wire.relayed(Writer, block, nil)
	end
end

local function tapWithheld(_: Key, block: Block.Block, _: buffer)
	Wire.withheldTap(Writer, block)
end

--[[
    Starts Turn in this worker's VM with the settings the front built for
    its own Turn.start, copied across the boundary, and this worker's ports,
    with its clocks while relay.clocks is on
--]]

function Remote.setup(settings: Settings)
	Changes = settings.changes
	Clock.on = settings.clocks == true
	if Clock.on then
		Clock.laps = buffer.create(Wire.CLOCK_BYTES)
	end

	Turn.start(settings, {
		send = send,
		sendWithheld = sendWithheld,
		heard = heard,
		traffic = traffic,
		isHidden = isHidden,
		valid = Slots.valid,
		observing = observing,
		observes = observes,
		relayed = relayed,
		withheld = tapWithheld,
	})
end

-- Writes the seconds since the part of the run being timed began as that part's, and begins the next part
local function lapped(at: number)
	local now: number = os.clock()
	buffer.writef64(Clock.laps, at, now - Clock.from)
	Clock.from = now
end

--[[
    One viewer's turn, the place from 1 in the list given: its recipients
    as its view's watchers stand, which open its section of the result,
    and the hand-in's answers, team and traffic for it
--]]

local function take(index: number)
	local viewer: Viewer = List[index]
	local hand: Hand = Hands[index]
	local key: Key = viewer.key
	local view: View? = Turn.view(key)
	if not view then
		error(`A relay worker's viewer {hand.id} has no view after Turn.ready`)
	end

	Recipients[1] = hand.id
	local count: number = 1
	local observed: boolean = Observed[key] == true

	if view.watcherCount > 0 then
		for bit: number = 1, MAX_WATCHERS do
			local watcher: Key? = view.watchers[bit]
			if watcher ~= nil then
				local id: number? = Ids[watcher]
				if id == nil then
					error(`A relay worker's watcher at bit {bit} of viewer {hand.id} has no id`)
				end

				count += 1
				Recipients[count] = id
				if Observed[watcher] then
					observed = true
				end
			end
		end
	end

	TurnRow = hand.row
	TurnTeam = hand.team
	TurnTraffic = hand.traffic
	TurnObserved = observed
	Wire.turn(Writer, index, Recipients, count)

	local back: number? = nil
	if hand.back then
		back = hand.sequence
	end

	Turn.turn(viewer, back, hand.missed)
end

--[[
    One run on this worker: the looks and Invisible marks set between runs,
    then the calls queued between runs, both as the front's world stood
    when they were made, then the run's bodies, then the viewers handed in,
    whose watches and turns run as the front's serial run of the same list
    would, the run before's footsteps kept for a turn the hand-in marks as
    following a run its viewer was left. A turn that throws is kept with
    its place and text and ends the turns after it here. Gives the run's
    result, and while relay.clocks is on its clocks, a buffer this worker
    keeps and rewrites every run
--]]

function Remote.run(shared: buffer, own: buffer): (buffer, buffer?)
	local clocked: boolean = Clock.on
	if clocked then
		Clock.from = os.clock()
	end

	Own = own

	-- A front that lost a result starts its copies again empty, so each view this worker runs from now goes whole
	if Wire.resend(own) then
		table.clear(Shadows)
	end

	-- A turn the hand-in marks as following a run its viewer was left hears the run before's footsteps, judged by that
	-- run's Invisible marks, so they are kept before this run's change them
	local count: number = Wire.readOwn(own, Hands)
	local missed: boolean = false
	for index: number = 1, count do
		if Hands[index].missed then
			missed = true
			Turn.hush()

			break
		end
	end

	local header: Shared = Header
	local at: number = Wire.readLooks(shared, World, header)

	for index: number = 1, Wire.callCount(own) do
		local kind: number, id: number, slot: number, value: number = Wire.readCall(own, index)
		local key: Key = handle(id)

		if kind == Wire.SHOT_NEAR then
			Turn.shotNear(key, slot, value)
		elseif kind == Wire.REVEAL then
			Turn.reveal(key, slot)
		elseif kind == Wire.REVEAL_ALL then
			Turn.revealAll(key, value)
		elseif kind == Wire.SET_DISTANCE then
			Turn.setDistance(key, value)
		elseif kind == Wire.REMOVE then
			Turn.remove(key)
			Shadows[key] = nil
			Leaving[key] = true
		else
			error(`A relay worker's queued call is of kind 1 to 5, not {kind}`)
		end
	end

	if clocked then
		lapped(AT.unpack)
	end

	-- The run before's footsteps are kept while one of this run's turns follows a run its viewer was left, so long as
	-- the world holds them, that run the last Turn filed, which a run that threw before filing never is
	local carry: boolean = missed and Turn.filed() == header.run - 1
	Turn.begin(header.run, header.tick, header.elapsed, header.wire, header.tune, carry)
	Wire.readBodies(shared, at, World, header, Changes)

	local places: number = header.places
	local walk: buffer = World.walk
	for place: number = 1, places do
		buffer.writeu16(Places, buffer.readu16(walk, place * 2) * 2, place)
	end

	if clocked then
		lapped(AT.bodies)
	end

	Turn.file(places)

	if clocked then
		lapped(AT.grid)
	end

	table.clear(Observed)
	for index: number = 1, header.observedCount do
		Observed[handle(header.observed[index])] = true
	end

	Observing = header.observing

	for index: number = 1, count do
		local hand: Hand = Hands[index]
		local viewer: Viewer = viewerAt(index)

		viewer.key = handle(hand.id)
		Leaving[viewer.key] = nil
		viewer.slot = hand.slot
		viewer.position = hand.position
		viewer.acknowledged = hand.acknowledged
		viewer.received = hand.received
		viewer.look = hand.look
		viewer.zoomed = hand.zoomed
		viewer.delay = hand.delay

		local target: number? = hand.target
		if target ~= nil then
			viewer.target = handle(target)
		else
			viewer.target = nil
		end

		List[index] = viewer
	end

	for index: number = count + 1, #List do
		List[index] = nil
	end

	Wire.begin(Writer, places)
	Turn.ready(List)

	-- A handle let go and not handed in again is forgotten once the sweep has taken it off its targets' views
	for key: Key in Leaving do
		local id: number? = Ids[key]
		if id ~= nil then
			forget(id)
		end
	end

	table.clear(Leaving)

	for index: number = 1, count do
		local viewer: Viewer = List[index]
		local target: Key? = viewer.target
		if target ~= nil then
			Wire.watch(Writer, Turn.watch(viewer, target, Hands[index].sequence))
		end
	end

	if clocked then
		lapped(AT.ready)
	end

	local failed: number = 0
	local failure: string = ""
	for index: number = 1, count do
		if List[index].target == nil then
			local ran: boolean, thrown: unknown = pcall(take, index)
			if not ran then
				failed = index
				failure = tostring(thrown)

				break
			end
		end
	end

	if clocked then
		lapped(AT.turns)
	end

	-- Every view due a turn this run, taken or not after a throw, as it now stands against what the front holds
	for index: number = 1, count do
		local viewer: Viewer = List[index]
		if viewer.target == nil then
			local key: Key = viewer.key
			local view: View? = Turn.view(key)
			if view then
				Wire.view(Writer, Hands[index].id, view, shadowOf(key))
			end
		end
	end

	if clocked then
		lapped(AT.views)
	end

	local sent: number, cut: number, visited: number, rest: number = Turn.counts()
	local result: buffer = Wire.finish(Writer, sent - Sent, cut - Cut, visited - Visited, rest - Rest, failed, failure)
	Sent = sent
	Cut = cut
	Visited = visited
	Rest = rest

	if not clocked then
		return result, nil
	end

	-- The turns' parts lead the clocks, as Turn.clocks lays them out
	lapped(AT.pack)
	buffer.copy(Clock.laps, 0, Turn.clocks())

	return result, Clock.laps
end

return Remote
