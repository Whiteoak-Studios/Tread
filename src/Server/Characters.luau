--[[
    The character, NPC, sleeper and body handles a game holds, and the
    server's bodies by slot behind them: their states, looks and commands,
    the queries over them, and the stages that step, record and relay them
--]]

--!strict
--!native
local Character = {}
Character.__index = Character

local Npc = {}
Npc.__index = Npc

local Sleeper = {}
Sleeper.__index = Sleeper

local Body = {}
Body.__index = Body

local Workspace = game:GetService("Workspace")

local AntiEsp = require(script.Parent.AntiEsp)
local Collide = require(script.Parent.Parent.Step.Collide)
local Command = require(script.Parent.Parent.Codec.Command)
local Commands = require(script.Parent.Commands)
local Config = require(script.Parent.Parent.Config)
local Connections = require(script.Parent.Connections)
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Parent.Step.Engine)
local Eye = require(script.Parent.Parent.Step.Eye)
local Fields = require(script.Parent.Parent.Codec.Fields)
local History = require(script.Parent.History)
local Hulls = require(script.Parent.Parent.Step.Hulls)
local Math = require(script.Parent.Parent.Step.Math)
local Npcs = require(script.Parent.Npcs)
local OwnerState = require(script.Parent.Parent.Codec.OwnerState)
local Platforms = require(script.Parent.Parent.Step.Platforms)
local Public = require(script.Parent.Parent.Step.Public)
local Range = require(script.Parent.Range)
local Record = require(script.Parent.Parent.Codec.Record)
local Relay = require(script.Parent.Relay)
local Reliable = require(script.Parent.Parent.Codec.Reliable)
local Reports = require(script.Parent.Reports)
local Sleepers = require(script.Parent.Sleepers)
local Slots = require(script.Parent.Slots)
local Spectate = require(script.Parent.Spectate)
local State = require(script.Parent.Parent.Step.State)
local Step = require(script.Parent.Parent.Step)
local Teleport = require(script.Parent.Teleport)
local Types = require(script.Parent.Parent.Types)
local World = require(script.Parent.Parent.Step.World)

local SLOTS: number = Constants.SLOTS
local PLAY_BOUND: number = Constants.PLAY_BOUND
local WRAP: number = 2 ^ 16 -- A wire tick and a command number are u16
local EPOCHS: number = 2 ^ 8 -- The full epoch is a u8, so one past its top wraps to 0
local RECENT: number = 8 -- The stepped commands a character keeps for rewindFor, each with its tick and queue wait
local NUMBER_BYTES: number = 2 -- A kept command's number, a u16
local TICK_BYTES: number = 8 -- Its tick, unwrapped, an f64
local MILLISECONDS: number = 1000 -- A second's, which a Move's interpolation delay counts in
local RIG: Slots.Rig = "A" -- The rig mode every body is drawn with, the one the first release has
local SIMULATE: string = "simulate" -- The stage a character's failed step is reported under
local MOVE_MODES: { [string]: boolean } = { Walk = true, Noclip = true, Parked = true } -- What setMode takes
local MAX_WATCHERS: number = Constants.MAX_WATCHERS -- The watchers one target takes
local FOCUS_RATE: number = 5 -- Hz each player's focus part is moved at, a share of the parts each relay tick
local FOCUS_HOLDER: string = "TreadFocus" -- The server-only Camera every focus part sits under

type Bot = Types.Bot
type Collision = State.Collision
type Command = State.Command
type Connection = Connections.Connection
type Entry = Fields.Entry
type Layout = Fields.Layout
type Limits = Command.Limits
type MoveMode = State.MoveMode
type Platform = State.Platform
type PlatformEntry = State.PlatformEntry
type Posture = State.Posture
type PublicState = Public.State
type ServerSettings = Config.ServerSettings
type Shape = Config.Shape
type Shared = Config.Shared
type StepState = State.State
type Values = State.Values
type Viewer = Relay.Viewer
type World = State.World

type Self = Types.Character
type SleeperSelf = Types.Sleeper
type BodySelf = Types.Body
type Key = Player | Bot

-- What a death message is fired with to the keys it goes to: the dying slot's id, the body's, and the push's steps
type SendDeath = (keys: { Key }, character: number, body: number, x: number, y: number, z: number) -> ()

-- What the server handle starts the bodies with: the game's checked tables, their compiled declarations, the
-- function that fires an OwnerState to its owner, which counts what it sends, and the one that fires a death
export type Context = {
	shared: Shared,
	server: ServerSettings,
	layout: Layout,
	sendOwner: (key: Key, data: buffer) -> (),
	sendDeath: SendDeath,
}

export type Sample = Types.Sample

-- A landing that counted, with the speed it met the ground at, the ground's material, water for one in water, and the
-- fall's apex
export type Landed = (target: Target, speed: number, material: Enum.Material, apex: number) -> ()

type NpcFields = {
	_inner: Npcs.Npc, -- The NPC the step moves
	_slot: number,
	_generation: number,
	_live: boolean, -- Until it dies or is destroyed
	_destroyed: boolean,
}

type Listener = { callback: Landed, connected: boolean }

-- The server's setup, from the context at start
type Setup = {
	world: World,
	layout: Layout,
	limits: Limits, -- The lean and cone limits OwnerState counts its steps to
	headCone: number,
	beforeCommand: (character: Self, command: Command) -> (),
	sendOwner: (key: Key, data: buffer) -> (),
	sendDeath: SendDeath,
	simulationRate: number, -- Hz
	relayRate: number,
	relayInterval: number, -- Seconds between relay ticks, the cadence each connection samples its ping at
	focusGroups: number, -- The shares the focus parts are moved in, one a relay tick, so each moves at FOCUS_RATE
	focusHolder: Camera, -- The server-only Camera the focus parts sit under
	bots: boolean, -- Whether the server settings give bots.rtt
	serverFields: { [string]: Entry }, -- The server-set declarations by name, which setField takes
	held: Fields.List, -- The held-item declarations, which a held item is checked against
}

local Running: Setup? = nil

-- Every live body by slot: its state, which the relay reads, and its last command's look, whose pitch and head offset
-- its record and its history carry
local States: { [number]: StepState } = {}
local Stepped: { [number]: Command } = {}

-- Each body's public state, refilled at most once a step: its steps so far, and the step it was last filled at
local Publics: { [number]: PublicState } = {}
local Versions: { [number]: number } = {}
local Filled: { [number]: number } = {}

local PublicSamples: { [number]: { [Posture]: Sample } } = {} -- Each slot's public samples, made at its first read

-- Each character's last RECENT stepped commands by slot: the number, the tick it ran on unwrapped, and its queue wait
local RecentNumbers: buffer = buffer.create(SLOTS * RECENT * NUMBER_BYTES)
local RecentTicks: buffer = buffer.create(SLOTS * RECENT * TICK_BYTES)
local RecentWaits: buffer = buffer.create(SLOTS * RECENT)
local RecentNext: buffer = buffer.create(SLOTS) -- The ring index the next one goes at
local RecentHeld: buffer = buffer.create(SLOTS) -- How many the ring holds

-- Each character by slot: its connection, its viewer the relay is handed, whether the game made it Invisible, and
-- whether its player left before the game destroyed it
local Links: { [number]: Connection } = {}
local Viewers: { [number]: Viewer } = {}
local Invisible: { [number]: boolean } = {}
local Departed: { [number]: boolean } = {}

local ByKey: { [Key]: Self } = {} -- Each player's or bot's character, until it leaves or is destroyed
local Owned: { [Self]: Connection } = {} -- Each character's connection, until destroy releases it
local Outfits: { [number]: Values } = {} -- Each slot's look as the game last set it, which a body is given at a death
local CharacterHandles: { [number]: Self } = {}
local NpcHandles: { [number]: NpcSelf } = {}
local SleeperHandles: { [number]: SleeperSelf } = {}

-- The live handles in slot order, each list replaced whole on a create or a destroy so a stage walking one keeps it
local CharacterList: { Self } = {}
local NpcList: { NpcSelf } = {}
local SleeperList: { SleeperSelf } = {}

local RelayTick: number = 0 -- The relay tick the relay stage last ran, unwrapped, so the next block rides the one after

-- Each platform's place at the tick the history or the relay stage last ran, by its id
local PlatformPlaces: { [number]: vector } = {}

-- Each player's focus part, its ReplicationFocus, the share of the parts it moves in, and the share the next one gets
local Focus: { [Player]: Part } = {}
local FocusGroups: { [Player]: number } = {}
local NextGroup: number = 0

local ViewerList: { Viewer } = {} -- This relay tick's viewers, refilled in place
local LandedListeners: { Listener } = {} -- Replaced whole on a connect or a disconnect, so a landing's walk keeps it

-- The Moves Volt's listener filed since the last decode, each one's values side by side
local PendingCount: number = 0
local PendingKeys: { [number]: Key } = {}
local PendingCommands: { [number]: number } = {}
local PendingAcknowledged: { [number]: number } = {}
local PendingReceived: { [number]: number } = {}
local PendingDelays: { [number]: number } = {}
local PendingWires: { [number]: { Command.Wire } } = {}

-- A body's state before its step, put back when the step throws, and the state being stepped, nil outside a step
local Before: StepState = State.new()
local SteppingState: StepState? = nil
local CurrentSlot: number = 0 -- The slot being stepped, which a failed step's warning names

-- OwnerState is written here, then copied into a buffer of its exact length, kept once per length, which Volt copies
local OwnerScratch: buffer = buffer.create(Constants.MAX_OWNER_STATE)
local OwnerBuffers: { [number]: buffer } = {}
local HeldScratch: buffer = buffer.create(Constants.MAX_HELD) -- A held item is packed here to check it
local LookScratch: buffer = buffer.create(Constants.MAX_LOOK) -- And a sleeper's look, before it takes a slot

local Characters = {}

-- The server's setup, erroring from the caller of the member named before Characters.start has run
local function running(member: string): Setup
	local setup: Setup? = Running
	if not setup then
		error(`{member} ran before the server started`, 3)
	end

	return setup
end

-- Errors from the caller of the member named when the handle has ended: died, slept, woke or been destroyed
local function live(handle: { _live: boolean }, member: string)
	if not handle._live then
		error(`{member} ran on a handle that has ended`, 3)
	end
end

-- A value less itself is 0 only when the value is finite
local function finite(value: number): boolean
	return value - value == 0
end

-- Names a player or bot in a refusal, and anything else by its type
local function nameOf(key: any): string
	if (typeof(key) == "Instance" or type(key) == "table") and type(key.Name) == "string" then
		return key.Name
	end

	return `a {typeof(key)}`
end

-- Errors from the caller of the member named when a value is no type a member takes
local function expect(value: any, kind: string, member: string, what: string)
	if typeof(value) ~= kind then
		error(`{member} takes {what} as a {kind}, not a {typeof(value)}`, 3)
	end
end

--[[
    A declared field's value when a body is built: its start, or for a field
    that gives none the value that holds nothing, false, the number nearest 0
    its range holds, an empty list, or a group of those
--]]

local function startOf(entry: Entry): any
	if entry.start ~= nil then
		return entry.start
	elseif entry.count > 0 then
		return {}
	elseif entry.type == "bool" then
		return false
	elseif entry.type == "group" then
		local group: Values = {}
		for _, inner: Entry in entry.fields do
			group[inner.name] = startOf(inner)
		end

		return group
	end

	return math.clamp(0, entry.min, entry.max)
end

-- Fills a new body's rule-state and server-set blocks from the game's declarations
local function fillBlocks(state: StepState, layout: Layout)
	for _, entry: Entry in layout.rules.entries do
		state.block[entry.name] = startOf(entry)
	end

	for _, entry: Entry in layout.server.entries do
		state.fields[entry.name] = startOf(entry)
	end
end

-- A copy of the game's values into a table of the body's own, nested lists and groups copied too
local function copyInto(from: Values, into: Values)
	table.clear(into)

	for key: string, value: any in from do
		if type(value) == "table" then
			local inner: Values = {}
			copyInto(value, inner)
			into[key] = inner
		else
			into[key] = value
		end
	end
end

-- The handles of one kind, in slot order, from their table by slot
local function listed<T>(bySlot: { [number]: T }): { T }
	local list: { T } = {}

	for slot: number = 0, SLOTS - 1 do
		local handle: T? = bySlot[slot]
		if handle ~= nil then
			table.insert(list, handle)
		end
	end

	return list
end

-- The live players' and NPCs' states in slot order, which the world's hull tests block against
local function bodies(): { StepState }
	local list: { StepState } = {}

	for slot: number = 0, SLOTS - 1 do
		if CharacterHandles[slot] ~= nil or NpcHandles[slot] ~= nil then
			table.insert(list, States[slot])
		end
	end

	return list
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

-- Readies a slot's body data for a new body, its look along facing, its public state empty and no step yet
local function claim(slot: number, state: StepState, facing: number)
	local look: Command = Command.new()
	look.yaw = facing

	States[slot] = state
	Stepped[slot] = look
	Publics[slot] = Public.new()
	Versions[slot] = 0
	Filled[slot] = -1
end

-- Forgets a slot's body data, for a destroy
local function forget(slot: number)
	States[slot] = nil
	Stepped[slot] = nil
	Publics[slot] = nil
	Versions[slot] = nil
	Filled[slot] = nil
	Links[slot] = nil
	Viewers[slot] = nil
	Invisible[slot] = nil
	Departed[slot] = nil
	Outfits[slot] = nil
end

-- Keeps a copy of the look the game set for a slot, so a body made from it is given the same
local function keepOutfit(slot: number, outfit: Values)
	local kept: Values = Outfits[slot] or {}
	Outfits[slot] = kept
	copyInto(outfit, kept)
end

--[[
    A CFrame's position on the step's vector and its look's facing, the
    step's yaw, erroring from the caller of the member named unless it is a
    CFrame whose position is finite inside the play bound and whose look is
    finite

    @ what | how the refusal names the CFrame, such as where to build the character
--]]

local function placeOf(at: CFrame, member: string, what: string): (vector, number)
	if typeof(at) ~= "CFrame" then
		error(`{member} takes {what} as a CFrame, not a {typeof(at)}`, 3)
	end

	local position: vector = Engine.toVector(at.Position)
	if not (math.abs(position.x) <= PLAY_BOUND and math.abs(position.z) <= PLAY_BOUND and finite(position.y)) then
		error(`{member} takes a finite position inside the {PLAY_BOUND}-stud play bound, not {at.Position}`, 3)
	end

	local look: Vector3 = at.LookVector
	local facing: number = math.atan2(-look.X, -look.Z)

	-- NaN is the one number that differs from itself
	if facing ~= facing then
		error(`{member} takes a CFrame whose look is finite, not {look}`, 3)
	end

	return position, facing
end

-- Keeps a stepped command's number, tick and queue wait in its character's ring, over the oldest when it is full
local function remember(slot: number, number: number, tick: number, wait: number)
	local at: number = buffer.readu8(RecentNext, slot)
	local index: number = slot * RECENT + at

	buffer.writeu16(RecentNumbers, index * NUMBER_BYTES, number)
	buffer.writef64(RecentTicks, index * TICK_BYTES, tick)
	buffer.writeu8(RecentWaits, index, wait)
	buffer.writeu8(RecentNext, slot, (at + 1) % RECENT)
	buffer.writeu8(RecentHeld, slot, math.min(buffer.readu8(RecentHeld, slot) + 1, RECENT))
end

-- Copies the look of a command a body stepped into the slot's own, so the record and the history read it later
local function keepLook(slot: number, command: Command)
	local look: Command = Stepped[slot]
	look.yaw = command.yaw
	look.pitch = command.pitch
	look.headYaw = command.headYaw
	look.headPitch = command.headPitch
end

-- A body's public state, filled from its state at most once a step, with its cleared eye and its last command's look
local function fill(slot: number, setup: Setup): PublicState
	local public: PublicState = Publics[slot]
	local version: number = Versions[slot]
	if Filled[slot] == version then
		return public
	end

	local state: StepState = States[slot]
	local world: World = setup.world
	local look: Command = Stepped[slot]
	local direction: vector = Public.look(look.yaw, look.pitch, look.headYaw, look.headPitch, setup.headCone)

	Public.fill(public, state, world, Eye.clear(state, world), direction)
	Filled[slot] = version

	return public
end

-- Runs where a landing callback's error was raised, so its warning keeps the callback's stack
local function warnLanded(message: any)
	warn(`A landing callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- Tells every landing callback of a landing, each under its own xpcall, making no table
local function landed(target: Target, speed: number, material: Enum.Material, apex: number)
	local listeners: { Listener } = LandedListeners

	for index: number = 1, #listeners do
		local listener: Listener = listeners[index]
		if listener.connected then
			xpcall(listener.callback, warnLanded, target, speed, material, apex)
		end
	end
end

-- What Npcs hands each NPC landing that counted, which reaches the landing callbacks with the NPC's handle
local function npcLanded(inner: Npcs.Npc, speed: number)
	local npc: NpcSelf? = NpcHandles[inner.slot]
	if npc then
		local state: StepState = States[inner.slot]
		landed(npc, speed, state.groundMaterial, state.apex)
	end
end

--[[
    Starts the bodies with the game's tables: the world on the game's own
    four collision functions or on engine casts over its include list, the
    NPCs and the teleports on that world, anti-ESP on its include list over
    the bodies' states, and the Camera the focus parts sit under. It runs
    once, after the slot table, the intake and the history start and before
    the first body
--]]

function Characters.start(context: Context)
	if Running then
		error("Characters.start runs once, and it has already run", 2)
	end

	local shared: Shared = context.shared
	local server: ServerSettings = context.server
	local layout: Layout = context.layout
	local collision: Collision = Engine.casts(shared.collision)
	local blocked: (origin: vector, direction: vector) -> boolean = Engine.occlusion(server.antiEsp.include)

	local world: World = World.new(shared.step, shared.rates.simulation, collision, shared.water, shared.rules, true)
	local serverFields: { [string]: Entry } = {}
	for _, entry: Entry in layout.server.entries do
		serverFields[entry.name] = entry
	end

	-- Never the Workspace's CurrentCamera, so it and the parts under it stay on the server
	local holder: Camera = Instance.new("Camera")
	holder.Name = FOCUS_HOLDER
	holder.Parent = Workspace

	Running = {
		world = world,
		layout = layout,
		limits = { lean = shared.step.lean, headCone = shared.step.headCone },
		headCone = shared.step.headCone,
		beforeCommand = server.beforeCommand,
		sendOwner = context.sendOwner,
		sendDeath = context.sendDeath,
		simulationRate = shared.rates.simulation,
		relayRate = shared.rates.relay,
		relayInterval = 1 / shared.rates.relay,
		focusGroups = math.max(math.round(shared.rates.relay / FOCUS_RATE), 1),
		focusHolder = holder,
		bots = server.bots ~= nil,
		serverFields = serverFields,
		held = layout.held,
	}

	Npcs.start(world, npcLanded)
	Teleport.start({ shared = shared, server = server }, world)
	AntiEsp.start({ shared = shared, server = server }, world, States, blocked)

	-- Connected before any game callback can be, and lives as long as the server
	Teleport.onTeleported(function (character: Self)
		AntiEsp.moved(character._slot)
	end)
end

--[[
    The Player a character is for, nil for one of Volt's bots, erroring from
    the caller of the member named on anything else, on a bot when the
    server settings give no bots.rtt, and on a key that has a character
--]]

local function ownerOf(key: Key, member: string, setup: Setup): Player?
	if typeof(key) == "Instance" then
		if not key:IsA("Player") then
			error(`{member} takes a Player or one of Volt's bots, not the {key.ClassName} {key:GetFullName()}`, 3)
		elseif ByKey[key] ~= nil then
			error(`{nameOf(key)} already has a character`, 3)
		end

		return key
	elseif type(key) ~= "table" or type(key.Name) ~= "string" then
		error(`{member} takes a Player or one of Volt's bots, not {nameOf(key)}`, 3)
	elseif not setup.bots then
		error(`The bot {key.Name} needs a server whose settings give bots.rtt`, 3)
	elseif ByKey[key] ~= nil then
		error(`{nameOf(key)} already has a character`, 3)
	end

	return nil
end

-- Gives a player their focus part, its ReplicationFocus, the first time they have a body, kept until they leave
local function focusFor(player: Player, position: vector, setup: Setup)
	if Focus[player] then
		return
	end

	local part: Part = Instance.new("Part")
	part.Name = player.Name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Position = Engine.toVector3(position)
	part.Parent = setup.focusHolder

	player.ReplicationFocus = part
	Focus[player] = part
	FocusGroups[player] = NextGroup
	NextGroup = (NextGroup + 1) % setup.focusGroups
end

--[[
    Makes the character a key's in a slot it holds with the state given:
    its connection, its viewer, its place in the range query, the step and
    the hull tests, and for a player its focus part
--]]

local function enlist(key: Key, player: Player?, slot: number, generation: number, state: StepState, setup: Setup): Self
	local connection: Connection = Connections.add(key)
	local position: vector = state.position
	Range.set(slot, position, key.Name)

	claim(slot, state, state.facing)
	buffer.writeu8(RecentNext, slot, 0)
	buffer.writeu8(RecentHeld, slot, 0)
	Links[slot] = connection
	Viewers[slot] = { key = key, slot = slot, position = position, acknowledged = 0, received = 0, target = nil }
	Invisible[slot] = false
	Departed[slot] = nil

	local fields: Types.CharacterFields = {
		player = key,
		_slot = slot,
		_generation = generation,
		_live = true,
		_kept = true,
		_destroyed = false,
	}
	local character: Self = setmetatable(fields, Character) :: any

	ByKey[key] = character
	Owned[character] = connection
	CharacterHandles[slot] = character
	CharacterList = listed(CharacterHandles)
	World.setBodies(setup.world, bodies())

	if player then
		focusFor(player, position, setup)
	end

	return character
end

--[[
    Builds a character for a player or one of Volt's bots in a free slot,
    its feet at the CFrame's position and facing along its look, after the
    exact depenetration a spawn runs, which reports a body no spot frees as
    stuck. Errors, naming the held-back count, when no slot is free
--]]

function Characters.create(key: Key, at: CFrame): Self
	local setup: Setup = running("server:create")
	local world: World = setup.world
	local player: Player? = ownerOf(key, "server:create", setup)
	local position: vector, facing: number = placeOf(at, "server:create", "where to build the character")

	local state: StepState = State.new()
	state.position = position
	state.facing = facing
	state.apex = position.y
	state.groundHeight = position.y
	state.eyeHeight = Math.quantizeEye(world.settings.eyeStanding)
	fillBlocks(state, setup.layout)

	-- Before the slot is taken, so a game collision function that throws here holds no slot
	local stuck: number? = Collide.depenetrate(state, world, true)

	local slot: number?, generation: number? = Slots.take("Player")
	if slot == nil or generation == nil then
		error("No slot was free for a player", 2)
	end

	Slots.setEntry(slot, { kind = "Player", rig = RIG, player = player })
	local character: Self = enlist(key, player, slot, generation, state, setup)

	if stuck then
		Reports.fire(key, "stuck", stuck)
	end

	return character
end

--[[
    Builds an NPC in a slot with no player, its feet at the CFrame's
    position and facing along its look, awake on a command with no input
--]]

function Characters.createNpc(at: CFrame): NpcSelf
	local setup: Setup = running("server:createNpc")
	expect(at, "CFrame", "server:createNpc", "where to build the NPC")

	local look: Vector3 = at.LookVector
	local facing: number = math.atan2(-look.X, -look.Z)
	local inner: Npcs.Npc = Npcs.create(Engine.toVector(at.Position), facing)
	local slot: number = inner.slot
	local state: StepState = inner:getState()

	fillBlocks(state, setup.layout)
	Slots.setEntry(slot, { kind = "Npc", rig = RIG })
	claim(slot, state, facing)

	local npc: NpcSelf = setmetatable({
		_inner = inner,
		_slot = slot,
		_generation = inner.generation,
		_live = true,
		_destroyed = false,
	}, Npc)

	NpcHandles[slot] = npc
	NpcList = listed(NpcHandles)
	World.setBodies(setup.world, bodies())

	return npc
end

-- A sleeper's handle for a slot that lies as one, in the sleepers' list
local function rest(slot: number, generation: number): SleeperSelf
	local fields: Types.SleeperFields = { _slot = slot, _generation = generation, _live = true }
	local sleeper: SleeperSelf = setmetatable(fields, Sleeper) :: any

	SleeperHandles[slot] = sleeper
	SleeperList = listed(SleeperHandles)

	return sleeper
end

--[[
    Builds a sleeper lying at the CFrame's position along its look, wearing
    the look given, for the game's rebuild of its sleepers at boot. Past the
    sleepers' share it builds none, gives nil and reports sleep with the
    sleepers held
--]]

function Characters.createSleeper(at: CFrame, outfit: Values): SleeperSelf?
	local setup: Setup = running("server:createSleeper")
	local position: vector, facing: number = placeOf(at, "server:createSleeper", "where to lay the sleeper")
	expect(outfit, "table", "server:createSleeper", "the sleeper's look")

	-- Packed once to check it, so a look its declarations don't hold is refused before a slot is taken
	Fields.write(setup.layout.slot, outfit, LookScratch, 0)

	local slot: number?, generation: number?, state: StepState? = Sleepers.create("Sleeper", position, facing)
	if slot == nil or generation == nil or state == nil then
		Reports.fire(nil, "sleep", Slots.count("Sleeper"))

		return nil
	end

	claim(slot, state, facing)
	Relay.setLook(slot, outfit)
	keepOutfit(slot, outfit)

	return rest(slot, generation)
end

--[[
    Every live character, NPC and sleeper, in that order, each in slot
    order, in a list of its own
--]]

function Characters.getAll(): { Target }
	local all: { Target } = {}

	for _, character: Self in CharacterList do
		if character._live then
			table.insert(all, character)
		end
	end

	for _, npc: NpcSelf in NpcList do
		if npc._live then
			table.insert(all, npc)
		end
	end

	for _, sleeper: SleeperSelf in SleeperList do
		if sleeper._live then
			table.insert(all, sleeper)
		end
	end

	return all
end

--[[
    The names of the players and bots whose characters stand within range
    of a point, the edge included
--]]

function Characters.near(at: Vector3, range: number): { string }
	expect(at, "Vector3", "server:near", "the point")

	return Range.near(Engine.toVector(at), range)
end

--[[
    The NPCs within range of a point, the edge included
--]]

function Characters.npcsNear(at: Vector3, range: number): { NpcSelf }
	expect(at, "Vector3", "server:npcsNear", "the point")

	local found: { NpcSelf } = {}
	for _, slot: number in Range.npcsNear(Engine.toVector(at), range) do
		local npc: NpcSelf? = NpcHandles[slot]
		if npc then
			table.insert(found, npc)
		end
	end

	return found
end

--[[
    Whether a box, its CFrame turned however the game's piece is, overlaps
    the hull of any live character or NPC that walks
--]]

function Characters.overlaps(cframe: CFrame, size: Vector3): boolean
	local setup: Setup = running("server:overlaps")
	expect(cframe, "CFrame", "server:overlaps", "the box's CFrame")
	expect(size, "Vector3", "server:overlaps", "the box's size")

	return Hulls.overlaps(Engine.box(cframe, size), setup.world)
end

-- The slot of a handle a game hands in, erroring from the caller of the member named on anything else
local function slotOf(target: Target, member: string): number
	local metatable: any = getmetatable(target :: any)
	if type(target) ~= "table" or (metatable ~= Character and metatable ~= Npc and metatable ~= Sleeper) then
		error(`{member} takes a character, an NPC or a sleeper, not a {typeof(target)}`, 3)
	end

	return target._slot
end

-- A capsule of the history's moved by an offset and crossed onto Vector3, into the public sample's own
local function cross(from: History.Shape, offset: vector, into: Shape)
	into.from = Engine.toVector3(from.from + offset)
	into.to = Engine.toVector3(from.to + offset)
	into.radius = from.radius
end

-- The public sample of a slot's posture, made at its first read with a capsule for each of the posture's zones
local function samplesOf(slot: number, sample: History.Sample): Sample
	local kept: { [Posture]: Sample } = PublicSamples[slot] or {}
	PublicSamples[slot] = kept

	local made: Sample? = kept[sample.posture]
	if made then
		return made
	end

	local zones: { [string]: Shape } = {}
	for name: string in sample.zones do
		zones[name] = { from = Vector3.zero, to = Vector3.zero, radius = 0 }
	end

	local public: Sample = {
		epoch = 0,
		position = Vector3.zero,
		yaw = 0,
		posture = sample.posture,
		body = { from = Vector3.zero, to = Vector3.zero, radius = 0 },
		zones = zones,
	}
	kept[sample.posture] = public

	return public
end

--[[
    A target's history read at a render time in relay ticks, its hit shapes
    placed, crossed onto Vector3, or nil for a time the history no longer
    holds, one spent in Noclip or Parked, or a target ended. A sleeper
    answers with its lying shapes, along its fall after a move, and a rider
    is placed on its platform as the platform stood at the command time, or
    at the render time with none. The sample is the slot's own table for
    its posture, which its next read rewrites

    @ commandTime | the shot's simulation tick, unwrapped, with its fraction
--]]

function Characters.sampleAt(target: Target, renderTime: number, commandTime: number?): Sample?
	local setup: Setup = running("server:sampleAt")

	local slot: number = slotOf(target, "server:sampleAt")
	if not target._live then
		return nil
	end

	local sample: History.Sample?
	if getmetatable(target :: any) == Sleeper then
		sample = Sleepers.sampleAt(slot, renderTime)
	else
		sample = History.sampleAt(slot, renderTime)
	end

	if not sample then
		return nil
	end

	-- A rider's sample is in its platform's frame, which a shot met where the shooter's copy of it stood
	local offset: vector = vector.zero
	if sample.platform ~= 0 then
		local tick: number = commandTime or renderTime * setup.simulationRate / setup.relayRate
		local platformAt: vector? = Platforms.at(setup.world, sample.platform, tick)
		if not platformAt then
			return nil
		end

		offset = platformAt
	end

	local public: Sample = samplesOf(slot, sample)
	public.epoch = sample.epoch
	public.position = Engine.toVector3(sample.position + offset)
	public.yaw = sample.yaw
	cross(sample.body, offset, public.body)

	for name: string, shape: History.Shape in sample.zones do
		cross(shape, offset, public.zones[name])
	end

	return public
end

--[[
    The render time a shot rewinds to, from one of the last RECENT commands
    the player's character stepped and the shot's claimed render time, and
    whether the claim was inside the band; a claim outside it is reported
    as band with its offset

    @ command | the number of the command the shot rode in, a u16
    @ renderTime | relay ticks with their fraction, the whole ticks full or their low 16 bits
--]]

function Characters.rewindFor(key: Key, command: number, renderTime: number): (number, boolean)
	running("server:rewindFor")

	local character: Self? = ByKey[key]
	if not character then
		error(`server:rewindFor takes a player with a character, and {nameOf(key)} has none`, 2)
	elseif type(command) ~= "number" then
		error(`server:rewindFor takes the command's number, not a {typeof(command)}`, 2)
	end

	local slot: number = character._slot
	for at: number = 0, buffer.readu8(RecentHeld, slot) - 1 do
		local index: number = slot * RECENT + at

		if buffer.readu16(RecentNumbers, index * NUMBER_BYTES) == command then
			local connection: Connection = Links[slot]
			local tick: number = buffer.readf64(RecentTicks, index * TICK_BYTES)
			local wait: number = buffer.readu8(RecentWaits, index)
			local delay: number = Commands.delay(connection) / MILLISECONDS

			local time: number, inside: boolean, offset: number =
				History.rewindFor(tick, connection:rtt(), connection:jitter(), wait, delay, renderTime)
			if not inside then
				Reports.fire(key, "band", offset)
			end

			return time, inside
		end
	end

	error(`server:rewindFor takes one of the last {RECENT} commands the character stepped, and {command} is none`, 2)
end

--[[
    Registers a ladder in the server's world and gives back the closure
    that removes it
--]]

function Characters.addLadder(cframe: CFrame, size: Vector3): () -> ()
	local setup: Setup = running("server:addLadder")
	expect(cframe, "CFrame", "server:addLadder", "the ladder's CFrame")
	expect(size, "Vector3", "server:addLadder", "the ladder's size")

	return World.addLadder(setup.world, cframe, size)
end

--[[
    Registers a moving platform in the server's world, whose boxes every
    body's step meets where its path puts it on the tick, and gives back the
    closure that removes it
--]]

function Characters.addPlatform(platform: Platform): () -> ()
	return Platforms.add(running("server:addPlatform").world, platform)
end

--[[
    Calls a registered platform on a simulation tick, unwrapped, so its path
    runs from that tick
--]]

function Characters.callPlatform(id: number, tick: number)
	Platforms.call(running("server:callPlatform").world, id, tick)
end

--[[
    Every registered platform by its id, the world's own table, with the two
    calls each keeps, for a join and a keyframe to read and leave as it is
--]]

function Characters.platforms(): { [number]: PlatformEntry }
	return running("Characters.platforms").world.platforms
end

--[[
    The players currently sent a target's current life, with the moderators
    spectating each viewer, bots among the viewers included, in a list of
    their own, none for a target ended
--]]

function Characters.viewersOf(target: Target): { Player }
	running("server:viewersOf")

	local slot: number = slotOf(target, "server:viewersOf")
	local players: { Player } = {}
	if not target._live then
		return players
	end

	for _, key: Key in Relay.viewersOf(slot) do
		if typeof(key) == "Instance" then
			table.insert(players, key :: Player)
		end

		-- A moderator watching a viewer sees the target on the viewer's screen, so a cue sent there reaches it too
		for _, moderator: Player in Spectate.spectatorsOf(key) do
			table.insert(players, moderator)
		end
	end

	return players
end

--[[
    A shooter's bullet passed near a viewer, so the viewer is sent the
    shooter's character faster for a time, while it is sent it at all. A
    shooter with no character is left as it is
--]]

function Characters.reportShotNear(shooter: Key, viewer: Key)
	running("server:reportShotNear")

	local character: Self? = ByKey[shooter]
	if character then
		Relay.shotNear(viewer, character._slot)
	end
end

--[[
    Starts a moderator spectating a target's character, switches it to a
    new one, or with nil ends it. The view the moderator gets starts on the
    next relay tick: a start or a switch makes every character the target
    is sent a fresh reveal on the target's own view, and an end does the
    same with the moderator's. A moderator with no character is refused, and
    so is a target's 32nd watcher, before anything changes
--]]

function Characters.spectate(moderator: Key, target: Self?)
	running("server:spectate")

	local own: Self? = ByKey[moderator]
	if not own or not own._live then
		error(`server:spectate takes a moderator with a character, and {nameOf(moderator)} has none`, 2)
	end

	local tick: number = (RelayTick + 1) % WRAP

	if target == nil then
		if Spectate.unwatch(moderator, tick) then
			Relay.revealAll(moderator)
		end

		return
	end

	local metatable: any = getmetatable(target :: any)
	if type(target) ~= "table" or metatable ~= Character or not target._live then
		error(`server:spectate takes a live character as its target, or nil to end, not a {typeof(target)}`, 2)
	end

	local key: Key = target.player
	local watchers: { Key }? = Spectate.watchers(key)
	if watchers and #watchers >= MAX_WATCHERS and not table.find(watchers, moderator) then
		error(`{nameOf(key)} already has the {MAX_WATCHERS} watchers one target takes`, 2)
	end

	Spectate.watch(moderator, key, Record.id(target._slot, target._generation), tick)
	Relay.revealAll(key)
end

--[[
    Ends every spectate of a key and the key's own, for a death, a sleep, a
    destroy or a leave, each moderator sent the end and given its own view
    back from the next relay tick
--]]

local function endSpectates(key: Key)
	local watchers: { Key }? = Spectate.watchers(key)
	local ended: { Key } = {}
	if watchers then
		table.move(watchers, 1, #watchers, 1, ended)
	end

	if Spectate.targetOf(key) ~= nil then
		table.insert(ended, key)
	end

	Spectate.leave(key, (RelayTick + 1) % WRAP)

	for _, moderator: Key in ended do
		Relay.revealAll(moderator)
	end
end

--[[
    Calls back on every landing that counted, a character's or an NPC's,
    with the target, its speed, the ground's material and the fall's apex.
    Returns the closure that disconnects the callback
--]]

function Characters.onLanded(callback: Landed): () -> ()
	if type(callback) ~= "function" then
		error(`server:onLanded takes a function, not a {typeof(callback)}`, 2)
	end

	local listener: Listener = { callback = callback, connected = true }
	local listeners: { Listener } = table.clone(LandedListeners)
	table.insert(listeners, listener)
	LandedListeners = listeners

	return function ()
		if listener.connected then
			listener.connected = false
			LandedListeners = without(LandedListeners, listener)
		end
	end
end

--[[
    What Volt's Move listener hands over for a player or bot, kept for the
    next tick's decode stage, which hands each to Commands. A Move from one
    with no character is dropped
--]]

function Characters.file(
	key: Key,
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	wires: { Command.Wire }
)
	if ByKey[key] == nil then
		return
	end

	local index: number = PendingCount + 1
	PendingCount = index
	PendingKeys[index] = key
	PendingCommands[index] = command
	PendingAcknowledged[index] = acknowledged
	PendingReceived[index] = received
	PendingDelays[index] = delay
	PendingWires[index] = wires
end

--[[
    A player or bot left Tread's Volt scope: it is no viewer from now, its
    connection record, its relay view, its anti-ESP pairs and its focus part
    go, every spectate of it and its own end, and a character the game has
    not destroyed yet keeps stepping on stand-ins until it does
--]]

function Characters.leave(key: Key)
	local character: Self? = ByKey[key]
	if character then
		ByKey[key] = nil

		if character._live then
			Departed[character._slot] = true
		end

		if Connections.get(key) == Owned[character] then
			Connections.remove(key)
		end
	end

	endSpectates(key)
	Relay.remove(key)
	AntiEsp.leave(key)

	if typeof(key) == "Instance" then
		local player: Player = key :: Player
		local part: Part? = Focus[player]
		Focus[player] = nil
		FocusGroups[player] = nil

		if part then
			part:Destroy()
		end
	end
end

--[[
    The decode stage: every Move filed since the last one, in the order it
    arrived, handed to Commands for its character's connection, and the
    references to Volt's tables let go; then every teleport ready or timed
    out set down, so the tick's Moves before it are dropped with the queue

    @ tick | the simulation tick as the server counts it, unwrapped
--]]

function Characters.decode(tick: number)
	local world: World = running("Characters.decode").world
	world.tick = tick % WRAP
	world.clock = tick

	local count: number = PendingCount
	PendingCount = 0

	for index: number = 1, count do
		local key: Key = PendingKeys[index]
		local wires: { Command.Wire } = PendingWires[index]
		PendingKeys[index] = nil
		PendingWires[index] = nil

		local character: Self? = ByKey[key]
		if character then
			Commands.receive(
				Links[character._slot],
				PendingCommands[index],
				PendingAcknowledged[index],
				PendingReceived[index],
				PendingDelays[index],
				wires
			)
		end
	end

	Teleport.run(tick)
end

--[[
    One character's step: its command or stand-in for the tick, kept for
    rewindFor, the game's pre-command hook, then the step against the live
    bodies, the range query and the landing and stuck reports
--]]

local function stepCharacter(character: Self, tick: number, wire: number, setup: Setup)
	local slot: number = character._slot
	local state: StepState = States[slot]
	local command: Command, _: boolean, wait: number = Commands.take(Links[slot], wire)

	remember(slot, command.number, tick, wait)
	setup.beforeCommand(character, command)

	-- The hook may have destroyed the character, which then takes no step
	if not character._live then
		return
	end

	State.copy(state, Before)
	SteppingState = state
	local speed: number, stuck: number? = Step.advance(state, command, setup.world)
	SteppingState = nil

	keepLook(slot, command)
	Spectate.stepped(character.player, command)
	Versions[slot] += 1
	Range.set(slot, state.position, character.player.Name)

	if stuck then
		Reports.fire(character.player, "stuck", stuck)
	end

	if speed > 0 then
		landed(character, speed, state.groundMaterial, state.apex)
	end
end

-- Runs where a character's step raised its error, so its warning keeps the stack
local function warnStep(message: any)
	local reason: string = debug.traceback(tostring(message), 2)
	warn(`The step of the character in slot {CurrentSlot} threw, and it was left unstepped for the tick: {reason}`)
end

--[[
    The simulate stage: each character in slot order, from a first slot
    that moves on by one each tick, each under its own xpcall, so one whose
    hook or rules throw is put back as it stood, reported as stage with its
    player, and every other character still steps
--]]

function Characters.simulate(tick: number)
	local setup: Setup = running("Characters.simulate")
	local wire: number = tick % WRAP
	setup.world.tick = wire
	setup.world.clock = tick

	local list: { Self } = CharacterList
	local count: number = #list
	local first: number = tick % math.max(count, 1)

	for offset: number = 0, count - 1 do
		local character: Self = list[(first + offset) % count + 1]
		if character._live then
			CurrentSlot = character._slot
			SteppingState = nil

			if not xpcall(stepCharacter, warnStep, character, tick, wire, setup) then
				local state: StepState? = SteppingState
				if state then
					State.copy(Before, state)
					SteppingState = nil
				end

				Reports.fire(character.player, "stage", SIMULATE)
			end
		end
	end
end

--[[
    The npcs stage: every awake NPC from its last command, each under the
    xpcall Npcs gives it, after every character has stepped
--]]

function Characters.npcs(tick: number)
	Npcs.step(tick % WRAP)

	for _, npc: NpcSelf in NpcList do
		if npc._live and npc._inner:isAwake() then
			Versions[npc._slot] += 1
		end
	end
end

-- Finds each registered platform's place at a simulation tick, unwrapped, forgetting the ones since removed
local function placePlatforms(world: World, tick: number)
	for id: number in PlatformPlaces do
		if world.platforms[id] == nil then
			PlatformPlaces[id] = nil
		end
	end

	for id: number in world.platforms do
		local at: vector? = Platforms.at(world, id, tick)
		if at then
			PlatformPlaces[id] = at
		end
	end
end

-- One body's sample, a rider's held in its platform's frame, which a platform removed this tick leaves unwritten
local function writeSample(slot: number, relayTick: number)
	local state: StepState = States[slot]
	local platform: number = state.platform
	if platform == 0 then
		History.write(slot, relayTick, state, Stepped[slot].pitch)

		return
	end

	local at: vector? = PlatformPlaces[platform]
	if at then
		History.write(slot, relayTick, state, Stepped[slot].pitch, at)
	end
end

--[[
    The history stage, on a relay tick: one sample for every character and
    every awake NPC, so an idle NPC's last sample answers for its idle time

    @ tick | the simulation tick as the server counts it, unwrapped, which places each platform
    @ relayTick | the relay tick it starts, unwrapped
--]]

function Characters.history(tick: number, relayTick: number)
	placePlatforms(running("Characters.history").world, tick)

	for _, character: Self in CharacterList do
		if character._live then
			writeSample(character._slot, relayTick)
		end
	end

	for _, npc: NpcSelf in NpcList do
		if npc._live and npc._inner:isAwake() then
			writeSample(npc._slot, relayTick)
		end
	end
end

-- Fires a character's OwnerState to its owner in a buffer of its exact length, with its queue depth set
local function sendOwnerState(slot: number, key: Key, connection: Connection, setup: Setup)
	local state: StepState = States[slot]
	state.depth = Commands.depth(connection)

	local length: number = OwnerState.write(state, OwnerScratch, 0, setup.layout, setup.limits)
	local data: buffer = OwnerBuffers[length] or buffer.create(length)
	OwnerBuffers[length] = data

	buffer.copy(data, 0, OwnerScratch, 0, length)
	setup.sendOwner(key, data)

	-- The moderators watching it get the same bytes beside the looks it stepped
	Spectate.feed(key, data, length)
end

--[[
    The slow pass behind each player's focus part: the parts whose share
    this relay tick is move to their player's body, or while the player
    spectates to the target's, and a player with no body to follow keeps
    the place it was last given
--]]

local function focus(relayTick: number, groups: number)
	local turn: number = relayTick % groups

	for player: Player, part: Part in Focus do
		if FocusGroups[player] ~= turn then
			continue
		end

		local followed: Key = player
		local target: Key? = Spectate.targetOf(player)
		if target ~= nil then
			followed = target
		end

		local character: Self? = ByKey[followed]
		if character and character._live then
			part.Position = Engine.toVector3(States[character._slot].position)
		end
	end
end

--[[
    The relay stage, on a relay tick: each character whose player is still
    here samples its ping, sends its OwnerState and is a viewer, with its
    acknowledgments and the target it spectates, then the relay gives every
    viewer its blocks, with each platform's place at the tick for its
    riders, and a share of the focus parts moves

    @ relayTick | the relay tick as the server counts it, unwrapped
    @ tick | the simulation tick that starts it, unwrapped
--]]

function Characters.relay(relayTick: number, tick: number)
	local setup: Setup = running("Characters.relay")
	local count: number = 0
	RelayTick = relayTick
	placePlatforms(setup.world, tick)

	for _, character: Self in CharacterList do
		local slot: number = character._slot
		if character._live and not Departed[slot] then
			local key: Key = character.player
			local connection: Connection = Links[slot]
			local viewer: Viewer = Viewers[slot]
			local acknowledged: number, received: number = Commands.acknowledged(connection)

			viewer.position = States[slot].position
			viewer.acknowledged = acknowledged
			viewer.received = received
			viewer.target = Spectate.targetOf(key)

			connection:sample(setup.relayInterval)
			sendOwnerState(slot, key, connection, setup)

			count += 1
			ViewerList[count] = viewer
		end
	end

	for index: number = #ViewerList, count + 1, -1 do
		ViewerList[index] = nil
	end

	Relay.run(relayTick, ViewerList, States, Stepped, PlatformPlaces)
	focus(relayTick, setup.focusGroups)
end

--[[
    How many live characters there are, and how many NPCs are awake, which
    stats reads
--]]

function Characters.counts(): (number, number)
	local players: number = 0
	for _, character: Self in CharacterList do
		if character._live then
			players += 1
		end
	end

	local awake: number = 0
	for _, npc: NpcSelf in NpcList do
		if npc._live and npc._inner:isAwake() then
			awake += 1
		end
	end

	return players, awake
end

--[[
    Takes a character out of the tick for a death, a sleep or a destroy,
    leaving its slot as it is: its teleport and every spectate of it end,
    and it leaves the step, the hull tests, the range query and the history
--]]

local function retire(character: Self, setup: Setup)
	local slot: number = character._slot
	character._live = false

	Teleport.cancel(slot)
	endSpectates(character.player)

	CharacterHandles[slot] = nil
	CharacterList = listed(CharacterHandles)
	World.setBodies(setup.world, bodies())
	Range.remove(slot)
	History.clear(slot)
end

-- A death's push as a unit vector, zero for none, erroring from the caller of the member named on anything else
local function pushOf(push: Vector3?, member: string): vector
	if push == nil then
		return vector.zero
	elseif typeof(push) ~= "Vector3" then
		error(`{member} takes the attack's direction as a Vector3 or nil, not a {typeof(push)}`, 3)
	end

	local direction: vector = Engine.toVector(push)
	local length: number = vector.magnitude(direction)
	if not (length < math.huge) then
		error(`{member} takes a finite direction for the attack, not {push}`, 3)
	elseif length == 0 then
		return vector.zero
	end

	return direction / length
end

--[[
    The keys a death goes to: every viewer sent the dying slot, its own
    player when it has one still here, and the moderators watching any of
    them, each once, in a list of its own
--]]

local function witnesses(slot: number, owner: Key?): { Key }
	local keys: { Key } = Relay.viewersOf(slot)
	if owner ~= nil then
		table.insert(keys, owner)
	end

	for index: number = 1, #keys do
		local watchers: { Key }? = Spectate.watchers(keys[index])
		if watchers then
			for _, watcher: Key in watchers do
				if not table.find(keys, watcher) then
					table.insert(keys, watcher)
				end
			end
		end
	end

	return keys
end

--[[
    Lays a body in a slot of its own where a dying slot's body lies, gives
    it the look the game last set, and sends the death, with the body's
    slot and generation and the push, to everyone who sees the dying slot.
    The body's slot table entry goes out before the death
--]]

local function bury(slot: number, generation: number, owner: Key?, push: vector, setup: Setup): BodySelf
	local state: StepState = States[slot]
	local bodySlot: number?, bodyGeneration: number?, lying: StepState? =
		Sleepers.create("Body", state.position, state.facing)
	if bodySlot == nil or bodyGeneration == nil or lying == nil then
		error("No slot was free for a body", 3)
	end

	claim(bodySlot, lying, state.facing)

	local outfit: Values? = Outfits[slot]
	if outfit then
		Relay.setLook(bodySlot, outfit)
		keepOutfit(bodySlot, outfit)
	end

	local dying: number, body: number, x: number, y: number, z: number =
		Reliable.writeDeath(slot, generation, bodySlot, bodyGeneration, push)
	setup.sendDeath(witnesses(slot, owner), dying, body, x, y, z)

	local fields: Types.BodyFields = { _slot = bodySlot, _generation = bodyGeneration, _live = true }

	return setmetatable(fields, Body) :: any
end

--- The state the last tick produced for the character, on Vector3: its
--- place, motion, mode and posture, its cleared eye and look, its hull
--- center and its standing and lying boxes. The same table until the next
--- tick refills it
--- @method getState
--- @within Character
--- @return State

function Character.getState(self: Self): PublicState
	live(self, "character:getState")

	return fill(self._slot, running("character:getState"))
end

--- Sets the character's move mode, after the game's own authority check:
--- Walk, Noclip, which flies through everything, or Parked, which holds it
--- still and sends it to no other player. Coming back to Walk runs the exact
--- depenetration, and a body no spot frees is reported as stuck
--- @method setMode
--- @within Character
--- @param mode MoveMode

function Character.setMode(self: Self, mode: MoveMode)
	live(self, "character:setMode")
	if not MOVE_MODES[mode] then
		error(`character:setMode takes Walk, Noclip or Parked, not {mode}`, 2)
	end

	local setup: Setup = running("character:setMode")
	local slot: number = self._slot
	local state: StepState = States[slot]
	local previous: MoveMode = state.moveMode
	state.moveMode = mode

	if previous ~= "Walk" and mode == "Walk" then
		local stuck: number? = Collide.depenetrate(state, setup.world, true)
		Range.set(slot, state.position, self.player.Name)

		if stuck then
			Reports.fire(self.player, "stuck", stuck)
		end
	end

	Relay.setInvisible(slot, Invisible[slot] or mode == "Parked")
end

--- The one teleport function: moves the character's feet to the CFrame's
--- position, facing along its look, once the destination is ready or the
--- teleport timeout passes, with its velocity zeroed, its epoch moved on
--- and its queued commands dropped, then raises onTeleported. It returns at
--- once, a second teleport replaces the first, and a death, a sleep or a
--- destroy cancels it
--- @method teleport
--- @within Character
--- @param at CFrame

function Character.teleport(self: Self, at: CFrame)
	live(self, "character:teleport")
	placeOf(at, "character:teleport", "where to move the character")

	Teleport.schedule(self, at, States[self._slot], Links[self._slot])
end

--- Puts the character in the Downed posture or takes it out. Out of it,
--- the character crouches, and the step stands it up through its usual
--- ceiling check
--- @method setDowned
--- @within Character
--- @param downed boolean

function Character.setDowned(self: Self, downed: boolean)
	live(self, "character:setDowned")
	if type(downed) ~= "boolean" then
		error(`character:setDowned takes true or false, not {downed}`, 2)
	end

	local state: StepState = States[self._slot]
	if downed then
		state.posture = "Downed"
	elseif state.posture == "Downed" then
		state.posture = "Crouch"
	end
end

--- Sets one of the game's declared server-set fields, such as being
--- revived, which the rules function reads and the owner's prediction
--- gets through OwnerState. A name the game declares no such field for, a
--- list or a group, or a value outside its declaration is refused
--- @method setField
--- @within Character
--- @param name string
--- @param value number | boolean

function Character.setField(self: Self, name: string, value: number | boolean)
	live(self, "character:setField")

	local entry: Entry? = running("character:setField").serverFields[name]
	if not entry then
		error(`character:setField takes a server-set field the game declares, and {name} is none`, 2)
	elseif entry.count > 0 or entry.type == "group" then
		error(`character:setField takes a number or a boolean, and {name} is a list or a group`, 2)
	elseif entry.type == "bool" then
		if type(value) ~= "boolean" then
			error(`character:setField takes true or false for {name}, not {value}`, 2)
		end
	elseif not (type(value) == "number" and value % 1 == 0 and value >= entry.min and value <= entry.max) then
		error(`character:setField takes a whole number from {entry.min} to {entry.max} for {name}, not {value}`, 2)
	end

	States[self._slot].fields[name] = value
end

--- Sets the character's look, the game's declared slot-table fields, which
--- each player sent the character gets with its reveal and again on each
--- change. A value outside its declaration is refused
--- @method setOutfit
--- @within Character
--- @param outfit Outfit

function Character.setOutfit(self: Self, outfit: Values)
	live(self, "character:setOutfit")
	expect(outfit, "table", "character:setOutfit", "the look's fields")

	Relay.setLook(self._slot, outfit)
	keepOutfit(self._slot, outfit)
end

--- Sets the character's held item, the game's declared held-item fields,
--- sent the way the look is, or empties its hands with nil. A value outside
--- its declaration is refused
--- @method setHeld
--- @within Character
--- @param held Held?

function Character.setHeld(self: Self, held: Values?)
	live(self, "character:setHeld")

	local into: Values = States[self._slot].held
	if held == nil then
		table.clear(into)

		return
	end

	expect(held, "table", "character:setHeld", "the held item's fields")

	-- Packed once to check it, so a value its declaration doesn't hold is refused here and never on the relay tick
	Fields.write(running("character:setHeld").held, held, HeldScratch, 0)
	copyInto(held, into)
end

--- Gives the character a team, nil for none. Two characters carrying the
--- same team are always sent each other, and anti-ESP hides neither from
--- the other. A new character starts with none
--- @method setTeam
--- @within Character
--- @param team number?

function Character.setTeam(self: Self, team: number?)
	live(self, "character:setTeam")

	-- NaN is the one number that differs from itself
	if team ~= nil and (type(team) ~= "number" or team ~= team) then
		error(`character:setTeam takes a team as a number or nil, not {team}`, 2)
	end

	AntiEsp.setTeam(self._slot, team)
end

--- Sends the character to no other player while on, teammates included,
--- or sends it again
--- @method setInvisible
--- @within Character
--- @param invisible boolean

function Character.setInvisible(self: Self, invisible: boolean)
	live(self, "character:setInvisible")
	if type(invisible) ~= "boolean" then
		error(`character:setInvisible takes true or false, not {invisible}`, 2)
	end

	local slot: number = self._slot
	Invisible[slot] = invisible
	Relay.setInvisible(slot, invisible or States[slot].moveMode == "Parked")
end

--- Turns the character into a sleeper in its slot, lying where it stands,
--- with its slot, its generation and its look kept, so each viewer lays
--- the same rig down. It leaves the step and every spectate of it ends,
--- and Invisible is cleared. Past the sleepers' share nothing changes, it
--- gives nil and reports sleep with the sleepers held. The game destroys
--- the character after
--- @method sleep
--- @within Character
--- @return Sleeper?

function Character.sleep(self: Self): SleeperSelf?
	live(self, "character:sleep")

	local setup: Setup = running("character:sleep")
	local slot: number = self._slot
	if not Sleepers.adopt(slot, States[slot]) then
		Reports.fire(self.player, "sleep", Slots.count("Sleeper"))

		return nil
	end

	retire(self, setup)
	self._kept = false

	-- The slot is the sleeper's now, lying level with nothing of the character's own left on it
	Relay.setInvisible(slot, false)
	Links[slot] = nil
	Viewers[slot] = nil
	Invisible[slot] = nil
	Departed[slot] = nil

	local look: Command = Stepped[slot]
	look.pitch = 0
	look.headYaw = 0
	look.headPitch = 0

	return rest(slot, self._generation)
end

--- Ends the character in a death: a body takes a slot of its own where it
--- lies, wearing its look, and the death, with the body's slot and
--- generation and the attack's direction for the ragdoll's push, nil for
--- none, goes to each player sent the character, its own player and the
--- moderators watching them. The character leaves the step, the relay,
--- the range query and the history at once, and the game destroys it after
--- @method die
--- @within Character
--- @param push Vector3?
--- @return Body

function Character.die(self: Self, push: Vector3?): BodySelf
	live(self, "character:die")

	local direction: vector = pushOf(push, "character:die")
	local setup: Setup = running("character:die")
	local slot: number = self._slot

	local owner: Key? = nil
	if not Departed[slot] then
		owner = self.player
	end

	local body: BodySelf = bury(slot, self._generation, owner, direction, setup)
	retire(self, setup)
	States[slot] = nil

	return body
end

--- Ends the character on its death, respawn or leave, releasing all it
--- still holds: its intake and connection record, and unless it slept its
--- slot, and before a death or a sleep its place in the step, the range
--- query, the history and every viewer's view. Its player's relay view
--- stays for the player's next character until the player leaves
--- @method destroy
--- @within Character

function Character.destroy(self: Self)
	if self._destroyed then
		error("character:destroy ran on a character already destroyed", 2)
	end

	local setup: Setup = running("character:destroy")
	local slot: number = self._slot
	local key: Key = self.player
	self._destroyed = true

	if self._live then
		retire(self, setup)
	end

	-- A player who left and came back may already own a newer character, whose record stays
	local connection: Connection? = Owned[self]
	Owned[self] = nil

	if ByKey[key] == self then
		ByKey[key] = nil
	end

	if connection then
		if Connections.get(key) == connection then
			Connections.remove(key)
		end

		Commands.remove(connection)
	end

	if self._kept then
		self._kept = false
		forget(slot)
		Slots.release(slot)
	end
end

local _: Types.CharacterOwn = Character

--- Issues the command the NPC steps from every tick while awake: its move,
--- buttons, look and the game's declared fields, its presses applied once
--- @method command
--- @within Npc
--- @param command Command

function Npc.command(self: NpcSelf, command: Command)
	live(self, "npc:command")
	self._inner:command(command)

	-- The look its record and history carry, the head offset held to the cone as the step holds it
	local cone: number = running("npc:command").headCone
	local look: Command = Stepped[self._slot]
	look.yaw = command.yaw
	look.pitch = command.pitch
	look.headYaw = math.clamp(command.headYaw, -cone, cone)
	look.headPitch = math.clamp(command.headPitch, -cone, cone)
end

--- Wakes the NPC or idles it. An idle NPC takes no step and keeps its last
--- history sample
--- @method setAwake
--- @within Npc
--- @param awake boolean

function Npc.setAwake(self: NpcSelf, awake: boolean)
	live(self, "npc:setAwake")
	self._inner:setAwake(awake)
end

--- The state the last tick produced for the NPC, as a character's
--- @method getState
--- @within Npc
--- @return State

function Npc.getState(self: NpcSelf): PublicState
	live(self, "npc:getState")

	return fill(self._slot, running("npc:getState"))
end

-- Takes an NPC out for good: its slot, its place in the range query, its history and its place in every view
local function retireNpc(npc: NpcSelf, setup: Setup)
	local slot: number = npc._slot
	npc._live = false

	History.clear(slot)
	forget(slot)

	NpcHandles[slot] = nil
	NpcList = listed(NpcHandles)
	World.setBodies(setup.world, bodies())
	npc._inner:destroy()
end

--- Ends the NPC in a death, as a character's: a body in a slot of its own
--- where it lies, the death sent to each player sent the NPC and the
--- moderators watching them, and the NPC out of everything at once
--- @method die
--- @within Npc
--- @param push Vector3?
--- @return Body

function Npc.die(self: NpcSelf, push: Vector3?): BodySelf
	live(self, "npc:die")

	local direction: vector = pushOf(push, "npc:die")
	local setup: Setup = running("npc:die")
	local body: BodySelf = bury(self._slot, self._generation, nil, direction, setup)
	retireNpc(self, setup)

	return body
end

--- Ends the NPC, releasing its slot, its place in the range query, its
--- history and its place in every viewer's view, or after a death nothing
--- more, since the death released them
--- @method destroy
--- @within Npc

function Npc.destroy(self: NpcSelf)
	if self._destroyed then
		error("npc:destroy ran on an NPC already destroyed", 2)
	end

	self._destroyed = true

	if self._live then
		retireNpc(self, running("npc:destroy"))
	end
end

--- Wakes the sleeper as a player's or a bot's character in the same slot,
--- with its generation kept, so viewers see the same body stand up where
--- its fall has it now, through the ceiling check. The history holds its
--- lying shapes up to now, and the epoch moves on. The key must have no
--- character, and a bot a server whose settings give bots.rtt
--- @method wake
--- @within Sleeper
--- @param player Player | Bot
--- @return Character

function Sleeper.wake(self: SleeperSelf, key: Key): Self
	live(self, "sleeper:wake")

	local setup: Setup = running("sleeper:wake")
	local player: Player? = ownerOf(key, "sleeper:wake", setup)
	local slot: number = self._slot
	local _, entry: Slots.Entry? = Slots.get(slot)
	if entry == nil then
		error(`sleeper:wake found no slot table entry for slot {slot}`, 2)
	end

	local state: StepState = States[slot]
	local lying: History.Lying = Sleepers.wake(slot, RelayTick)

	self._live = false
	SleeperHandles[slot] = nil
	SleeperList = listed(SleeperHandles)

	Slots.setEntry(slot, { kind = "Player", rig = entry.rig, player = player })
	fillBlocks(state, setup.layout)
	History.seed(slot, RelayTick, lying)
	state.posture = "Crouch"
	state.epoch = (state.epoch + 1) % EPOCHS

	local character: Self = enlist(key, player, slot, self._generation, state, setup)

	-- The step's own depenetration runs at its next Walk step, so a game collision function that throws only warns
	local cleared: boolean, stuck: any = pcall(Collide.depenetrate, state, setup.world, true)
	if not cleared then
		warn(`The woken character in slot {slot} wasn't depenetrated, since the collision threw: {stuck}`)
	elseif stuck then
		Reports.fire(key, "stuck", stuck)
	end

	return character
end

--- Moves the sleeper to lie at the CFrame's position along its look,
--- keeping its slot and generation. Its hit shapes take the fall from the
--- next relay tick, each viewer sent it gets a fresh reveal it draws as a
--- fall, and its anti-ESP pairs are tested again at once
--- @method moveTo
--- @within Sleeper
--- @param at CFrame

function Sleeper.moveTo(self: SleeperSelf, at: CFrame)
	live(self, "sleeper:moveTo")

	local position: vector, facing: number = placeOf(at, "sleeper:moveTo", "where to move the sleeper")
	local slot: number = self._slot

	Sleepers.move(slot, position, facing, RelayTick + 1)
	Relay.reveal(slot)
	AntiEsp.moved(slot)
end

--- Removes the sleeper, as at a kill, releasing its slot, so every viewer
--- sent it gets a hide
--- @method destroy
--- @within Sleeper

function Sleeper.destroy(self: SleeperSelf)
	live(self, "sleeper:destroy")
	self._live = false

	local slot: number = self._slot
	SleeperHandles[slot] = nil
	SleeperList = listed(SleeperHandles)

	forget(slot)
	Sleepers.remove(slot)
end

local _: Types.SleeperOwn = Sleeper

--- Removes the body, releasing its slot, so every viewer sent it gets a
--- hide
--- @method destroy
--- @within Body

function Body.destroy(self: BodySelf)
	live(self, "body:destroy")
	self._live = false

	forget(self._slot)
	Sleepers.remove(self._slot)
end

local _: Types.BodyOwn = Body

export type Character = Self
export type Npc = NpcSelf
export type Sleeper = SleeperSelf
export type Body = BodySelf
export type Target = Self | NpcSelf | SleeperSelf
type NpcSelf = typeof(setmetatable({} :: NpcFields, Npc))

return Characters
