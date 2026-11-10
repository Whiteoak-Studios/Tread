--[[
    The recording taps moderator clips are made from: each relay tick's frame
    for the sinks observing a viewer, every command stepped and every change
    to the reliable state for their callbacks, and that state's snapshot
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Codec.Block)
local Command = require(script.Parent.Parent.Codec.Command)
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Parent.Step.Engine)
local Feed = require(script.Parent.Parent.Codec.Feed)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Public = require(script.Parent.Parent.Step.Public)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local Tap = require(script.Parent.Parent.Codec.Tap)
local Types = require(script.Parent.Parent.Types)

local SLOTS: number = Constants.SLOTS
local MAX_COMMANDS: number = Constants.MAX_COMMANDS -- The looks a frame keeps, a Move's worth, as the feed keeps
local BODY_START: number = 1024 -- The bytes a viewer's frame body starts with, doubled whenever a block passes them
local MILLISECONDS: number = 1000 -- A second's, which a frame's view lag counts in
local MAX_LAG: number = 2 ^ 16 - 1 -- The milliseconds a frame's u16 view lag holds, a longer lag held at it

type Bot = Types.Bot
type Change = Types.Change
type Character = Types.Character
type Command = State.Command
type Key = Player | Bot
type Layout = Fields.Layout
type Limits = Command.Limits
type PublicState = Public.State
type Reason = Tap.Reason
type Sink = Types.Sink
type SlotEntry = Types.SlotEntry

-- What onCommand's and onReliable's callbacks are handed
export type Stepped = (
	character: Character,
	tick: number,
	command: Command,
	isStandIn: boolean,
	state: PublicState
) -> ()
export type Changed = (change: Change) -> ()

type Listener<T> = { callback: T, connected: boolean }

-- What the server handle starts the taps with: the compiled declarations, anti-ESP's reason a viewer is sent a
-- slot, and the relay's look and held item a slot wears
export type Settings = {
	layout: Layout,
	reason: (key: Key, slot: number) -> Reason,
	wearing: (slot: number) -> (buffer, buffer),
}

type Setup = {
	hash: number, -- The declarations' hash, which a snapshot carries
	reason: (key: Key, slot: number) -> Reason,
	wearing: (slot: number) -> (buffer, buffer),
}

-- One viewer the sinks of one tap observe, and the frame this relay run fills for them
type Observer = {
	sinks: { Listener<Sink> }, -- Replaced whole on a connect or a disconnect, so a tick's walk keeps it
	body: buffer, -- The blocks so far, each behind its length with its reasons after it
	filled: number,
	blocks: number,
	owner: buffer?, -- The OwnerState handed this run, kept in a buffer made at the first
	ownerLength: number, -- 0 while none was handed this run
	ownerId: number, -- The slot and generation of the character it is for
	lag: number, -- Its view lag in milliseconds
	limits: Limits?, -- The game's lean and cone limits the looks step to, handed with the OwnerState
	looks: { Command }, -- The looks the viewer stepped since the last frame, newest first and the first count current
	count: number,
}

local Running: Setup? = nil

local Observers: { [Key]: Observer } = {} -- Each viewer whose blocks a sink observes
local Withholders: { [Key]: Observer } = {} -- Each viewer whose withheld records a sink observes
local CommandListeners: { Listener<Stepped> } = {} -- Each replaced whole, as an observer's sinks are
local ReliableListeners: { Listener<Changed> } = {}

local Reasons: { Reason } = {} -- The send reasons of the block a tap is taking, refilled for each
local Ready: { Observer } = {} -- This tick's observers, beside their frames, while their sinks are called
local Frames: { buffer } = {}

local Taps = {
	-- Whether a sink observes any viewer's blocks or withheld records, which the relay and the relay stage read
	-- before each of their taps, so nothing more runs while none does
	observing = false,
	commanding = false, -- Whether onCommand has a callback, which the simulate stage reads before its tap
	reliable = false, -- Whether onReliable has one, which each change reads before its tap
}

-- The taps' setup, erroring from the caller of the member named before Taps.start has run
local function running(member: string): Setup
	local setup: Setup? = Running
	if not setup then
		error(`{member} ran before the server started`, 3)
	end

	return setup
end

-- A copy of a list with one value taken out
local function without<T>(list: { T }, value: T): { T }
	local kept: { T } = table.clone(list)
	local index: number? = table.find(kept, value)
	if index then
		table.remove(kept, index)
	end

	return kept
end

-- Errors from the caller of the member named on a viewer that is neither a Player nor one of Volt's bots
local function expectViewer(viewer: Key, member: string)
	if typeof(viewer) == "Instance" then
		if not viewer:IsA("Player") then
			error(`{member} takes a Player or one of Volt's bots, not the {viewer.ClassName} {viewer:GetFullName()}`, 3)
		end
	elseif type(viewer) ~= "table" or type(viewer.Name) ~= "string" then
		error(`{member} takes a Player or one of Volt's bots, not a {typeof(viewer)}`, 3)
	end
end

-- Errors from the caller of the member named when a callback is no function
local function expectFunction(callback: any, member: string)
	if type(callback) ~= "function" then
		error(`{member} takes a function, not a {typeof(callback)}`, 3)
	end
end

-- Whether any sink observes anything, kept on Taps for the relay to read
local function settle()
	Taps.observing = next(Observers) ~= nil or next(Withholders) ~= nil
end

--[[
    Starts the taps with the game's compiled declarations, anti-ESP's
    reason for a pair and the relay's look and held item for a slot. It
    runs once
--]]

function Taps.start(settings: Settings)
	if Running then
		error("Taps.start runs once, and it has already run", 2)
	elseif type(settings.reason) ~= "function" or type(settings.wearing) ~= "function" then
		error("Taps.start takes reason and wearing as functions", 2)
	end

	Running = {
		hash = Fields.hash(settings.layout),
		reason = settings.reason,
		wearing = settings.wearing,
	}
end

--[[
    Connects a sink to one of the two observer maps, made for the viewer at
    its first sink, and gives back the closure that disconnects it, which
    drops the viewer once its last sink goes
--]]

local function connect(map: { [Key]: Observer }, key: Key, sink: Sink, member: string): () -> ()
	running(member)
	expectViewer(key, member)
	expectFunction(sink, member)

	local kept: Observer? = map[key]
	local listening: Observer
	if kept then
		listening = kept
	else
		-- A table for each look a frame keeps, so stepping a command makes none
		local looks: { Command } = {}
		for index: number = 1, MAX_COMMANDS do
			looks[index] = Command.new()
		end

		listening = {
			sinks = {} :: { Listener<Sink> },
			body = buffer.create(BODY_START),
			filled = 0,
			blocks = 0,
			owner = nil :: buffer?,
			ownerLength = 0,
			ownerId = 0,
			lag = 0,
			limits = nil :: Limits?,
			looks = looks,
			count = 0,
		}
		map[key] = listening
	end

	local listener: Listener<Sink> = { callback = sink, connected = true }
	local sinks: { Listener<Sink> } = table.clone(listening.sinks)
	table.insert(sinks, listener)
	listening.sinks = sinks
	settle()

	return function ()
		if not listener.connected then
			return
		end

		listener.connected = false
		listening.sinks = without(listening.sinks, listener)

		if #listening.sinks == 0 and map[key] == listening then
			map[key] = nil
			settle()
		end
	end
end

--[[
    Tap 1: calls a sink once every relay tick, after relevancy, the tiers,
    the allocator and anti-ESP, with each block the relay sent the viewer
    that tick, a moderator's copies of its target's included, each record's
    send reason beside it, and the viewer's OwnerState while it owns a
    character, with its view lag and the looks it stepped since the last
    frame. A viewer sent nothing gets a frame with no blocks
--]]

function Taps.observe(viewer: Key, sink: Sink): () -> ()
	return connect(Observers, viewer, sink, "server:observe")
end

--[[
    Tap 5: calls a sink once every relay tick with the withheld blocks of a
    viewer a moderator spectates, the culled players anti-ESP held back from
    it, never an Invisible or Parked one, with their look entries and each
    record's reason, and a frame with no blocks while no one spectates it
--]]

function Taps.observeWithheld(viewer: Key, sink: Sink): () -> ()
	return connect(Withholders, viewer, sink, "server:observeWithheld")
end

--[[
    Taps 2 and 3: calls back with every command a character steps, a
    stand-in included, the base look at full precision, and the state the
    step produced. The command and the state are valid during the call
--]]

function Taps.onCommand(callback: Stepped): () -> ()
	running("server:onCommand")
	expectFunction(callback, "server:onCommand")

	local listener: Listener<Stepped> = { callback = callback, connected = true }
	local listeners: { Listener<Stepped> } = table.clone(CommandListeners)
	table.insert(listeners, listener)
	CommandListeners = listeners
	Taps.commanding = true

	return function ()
		if listener.connected then
			listener.connected = false
			CommandListeners = without(CommandListeners, listener)
			Taps.commanding = #CommandListeners > 0
		end
	end
end

--[[
    Tap 4: calls back with every change to the state a snapshot holds, a
    slot's entry, its look, its held item or a death, with the value before
    it, so a recorder walks back from a snapshot to its ring's start
--]]

function Taps.onReliable(callback: Changed): () -> ()
	running("server:onReliable")
	expectFunction(callback, "server:onReliable")

	local listener: Listener<Changed> = { callback = callback, connected = true }
	local listeners: { Listener<Changed> } = table.clone(ReliableListeners)
	table.insert(listeners, listener)
	ReliableListeners = listeners
	Taps.reliable = true

	return function ()
		if listener.connected then
			listener.connected = false
			ReliableListeners = without(ReliableListeners, listener)
			Taps.reliable = #ReliableListeners > 0
		end
	end
end

--[[
    Tap 4's snapshot: every taken slot, in slot order, with its generation,
    kind, rig mode, look and held item, in a new buffer
--]]

function Taps.snapshot(): buffer
	local setup: Setup = running("server:snapshot")
	local entries: { Tap.Entry } = {}

	for slot: number = 0, SLOTS - 1 do
		local generation: number, entry: Slots.Entry? = Slots.get(slot)
		if entry then
			local look: buffer, held: buffer = setup.wearing(slot)
			table.insert(entries, {
				slot = slot,
				generation = generation,
				kind = entry.kind,
				rig = entry.rig,
				look = look,
				held = held,
			})
		end
	end

	return Tap.writeSnapshot({ hash = setup.hash, slots = entries })
end

-- Fills Reasons with why each record of a block went, as anti-ESP answers for the viewer whose view it is
local function explain(key: Key, block: Block.Block, setup: Setup)
	local reason: (key: Key, slot: number) -> Reason = setup.reason
	local records: { number } = block.records
	local data: buffer = block.recordData

	for index: number = 1, block.recordCount do
		Reasons[index] = reason(key, buffer.readu16(data, records[index]) % SLOTS)
	end
end

-- Adds a block with the reasons Reasons holds to an observer's frame, its body grown when it would pass the end
local function append(observer: Observer, data: buffer, records: number)
	local needed: number = observer.filled + Tap.blockBytes(buffer.len(data), records)
	local body: buffer = observer.body

	if needed > buffer.len(body) then
		local grown: buffer = buffer.create(math.max(needed, buffer.len(body) * 2))
		buffer.copy(grown, 0, body, 0, observer.filled)
		observer.body = grown
	end

	observer.filled = Tap.writeBlock(observer.body, observer.filled, data, Reasons, records)
	observer.blocks += 1
end

--[[
    The relay's tap on each block it sends: for every one of its recipients
    a sink observes, the block's bytes and each record's reason, which
    anti-ESP gives for the first recipient, the viewer whose view it is
--]]

function Taps.relayed(keys: { Key }, count: number, block: Block.Block, data: buffer)
	local setup: Setup = running("Taps.relayed")
	local explained: boolean = false

	for index: number = 1, count do
		local observer: Observer? = Observers[keys[index]]
		if observer then
			if not explained then
				explain(keys[1], block, setup)
				explained = true
			end

			append(observer, data, block.recordCount)
		end
	end
end

--[[
    The relay's tap on each withheld block it sends for a target, which the
    sinks observing the target's withheld records take, each record's
    reason the one anti-ESP gives for holding it back from the target
--]]

function Taps.withheld(target: Key, block: Block.Block, data: buffer)
	local setup: Setup = running("Taps.withheld")

	local observer: Observer? = Withholders[target]
	if observer then
		explain(target, block, setup)
		append(observer, data, block.recordCount)
	end
end

--[[
    The relay stage's tap on each OwnerState it sends, kept for the frame of
    the viewer it went to, with the slot and generation of its character,
    the viewer's view lag in milliseconds, held at a u16's top, and the
    game's limits its looks step to

    @ lag | the seconds History.lag gives for the OwnerState's last command, 0 when left out
--]]

function Taps.owner(key: Key, id: number, data: buffer, lag: number?, limits: Limits?)
	local observer: Observer? = Observers[key]
	if not observer then
		return
	end

	local length: number = buffer.len(data)
	local kept: buffer = observer.owner or buffer.create(Constants.MAX_OWNER_STATE)
	observer.owner = kept

	buffer.copy(kept, 0, data, 0, length)
	observer.ownerLength = length
	observer.ownerId = id
	observer.lag = math.clamp(math.round((lag or 0) * MILLISECONDS), 0, MAX_LAG)
	observer.limits = limits
end

--[[
    The simulate stage's tap on each command a character stepped, its look
    kept for the frame of the viewer whose character it is, newest first,
    the oldest dropped past a Move's worth as the feed drops it. A viewer
    no sink observes keeps nothing
--]]

function Taps.stepped(key: Key, command: Command)
	local observer: Observer? = Observers[key]
	if not observer then
		return
	end

	observer.count = Feed.push(observer.looks, observer.count, command)
end

-- Runs where a sink's error was raised, so its warning keeps the sink's stack
local function warnSink(message: unknown)
	warn(`A tap's sink threw, and the other sinks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- An observer's frame for the tick, its run's blocks, OwnerState and looks emptied for the next
local function frameOf(observer: Observer, tick: number): buffer
	local frame: buffer = Tap.frame(
		tick,
		observer.blocks,
		observer.body,
		observer.filled,
		observer.owner,
		observer.ownerLength,
		observer.ownerId,
		observer.lag,
		observer.looks,
		observer.count,
		observer.limits
	)

	observer.filled = 0
	observer.blocks = 0
	observer.ownerLength = 0
	observer.lag = 0
	observer.count = 0

	return frame
end

--[[
    Ends the relay tick for the taps: every observed viewer's frame is made,
    then handed to each of its sinks under its own xpcall, so one that
    throws is warned with its stack and stops nothing else

    @ tick | the relay tick as the server counts it, unwrapped
--]]

function Taps.finish(tick: number)
	local count: number = 0

	-- Every frame is made before any sink runs, so a sink that connects or disconnects one changes no frame
	for _, observer: Observer in Observers do
		count += 1
		Ready[count] = observer
		Frames[count] = frameOf(observer, tick)
	end

	for _, observer: Observer in Withholders do
		count += 1
		Ready[count] = observer
		Frames[count] = frameOf(observer, tick)
	end

	for index: number = 1, count do
		local sinks: { Listener<Sink> } = Ready[index].sinks
		local frame: buffer = Frames[index]

		Ready[index] = nil
		Frames[index] = nil

		for _, listener: Listener<Sink> in sinks do
			if listener.connected then
				xpcall(listener.callback, warnSink, tick, frame)
			end
		end
	end
end

-- Takes a viewer out of one observer map, each of its sinks disconnected
local function forget(map: { [Key]: Observer }, key: Key)
	local observer: Observer? = map[key]
	if not observer then
		return
	end

	for _, listener: Listener<Sink> in observer.sinks do
		listener.connected = false
	end

	map[key] = nil
end

--[[
    Forgets a viewer that left: no sink of its is called again, and one
    its game disconnects later does nothing
--]]

function Taps.leave(key: Key)
	forget(Observers, key)
	forget(Withholders, key)
	settle()
end

-- Runs where a command callback's error was raised, so its warning keeps the callback's stack
local function warnCommand(message: unknown)
	warn(`A command callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

--[[
    The simulate stage's tap on each command a character stepped, with the
    simulation tick it ran on, unwrapped, whether it was a stand-in, and
    the character's public state after the step
--]]

function Taps.command(character: Character, tick: number, command: Command, isStandIn: boolean, state: PublicState)
	local listeners: { Listener<Stepped> } = CommandListeners

	for index: number = 1, #listeners do
		local listener: Listener<Stepped> = listeners[index]
		if listener.connected then
			xpcall(listener.callback, warnCommand, character, tick, command, isStandIn, state)
		end
	end
end

-- Runs where a change callback's error was raised, so its warning keeps the callback's stack
local function warnChange(message: unknown)
	warn(`A reliable change callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- Tells every change callback of one change, each under its own xpcall
local function changed(change: Change)
	local listeners: { Listener<Changed> } = ReliableListeners

	for index: number = 1, #listeners do
		local listener: Listener<Changed> = listeners[index]
		if listener.connected then
			xpcall(listener.callback, warnChange, change)
		end
	end
end

-- A slot table entry as a change reports it, with the look and held item the slot wears now, nil for a free slot
local function entryOf(slot: number, generation: number, entry: Slots.Entry?, setup: Setup): SlotEntry?
	if entry == nil then
		return nil
	end

	local look: buffer, held: buffer = setup.wearing(slot)

	return {
		generation = generation,
		kind = entry.kind,
		rig = entry.rig,
		look = look,
		held = held,
	}
end

--[[
    The slot table's tap on each change: a slot taken, changed in kind or
    rig, or freed, its entry before and after with the look and held item
    the slot wears as it changes
--]]

function Taps.slot(slot: number, generation: number, previous: Slots.Entry?, current: Slots.Entry?)
	local setup: Setup = running("Taps.slot")

	changed({
		slot = slot,
		kind = "slot",
		previous = entryOf(slot, generation, previous, setup),
		current = entryOf(slot, generation, current, setup),
	})
end

--[[
    The relay's tap on each look it is given for a slot's life, the look
    before it empty while none was set for that life
--]]

function Taps.look(slot: number, previous: buffer, current: buffer)
	changed({ slot = slot, kind = "look", previous = previous, current = current })
end

--[[
    The relay's tap on each held item it packs for a slot that differs from
    the one before, each empty while nothing is held
--]]

function Taps.held(slot: number, previous: buffer, current: buffer)
	changed({ slot = slot, kind = "held", previous = previous, current = current })
end

--[[
    The death's tap: the dying slot, the dying character's and the body's
    u16 slot and generation, and the push, a unit vector or zero for none
--]]

function Taps.death(slot: number, character: number, body: number, push: vector)
	changed({
		slot = slot,
		kind = "death",
		previous = nil,
		current = { character = character, body = body, push = Engine.toVector3(push) },
	})
end

return Taps
