--[[
    The one teleport function behind character:teleport: each move held until
    its destination is ready or its time runs out, then set down at the end of
    a tick's decode with the epoch bumped and the queued commands dropped
--]]

--!strict
local Workspace = game:GetService("Workspace")

local Collide = require(script.Parent.Parent.Step.Collide)
local Commands = require(script.Parent.Commands)
local Config = require(script.Parent.Parent.Config)
local Connections = require(script.Parent.Connections)
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Parent.Step.Engine)
local Mantle = require(script.Parent.Parent.Step.Mantle)
local Range = require(script.Parent.Range)
local Reports = require(script.Parent.Reports)
local Slide = require(script.Parent.Parent.Step.Slide)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local Types = require(script.Parent.Parent.Types)

local SLOTS: number = Constants.SLOTS
local PLAY_BOUND: number = Constants.PLAY_BOUND
local EPOCHS: number = 2 ^ 8 -- The full epoch is a u8, so one past its top wraps to 0
local DECODE: string = "decode" -- The stage a landing runs at the end of, which a failed one is reported under

type Bot = Types.Bot
type Character = Types.Character
type Connection = Connections.Connection
type ServerSettings = Config.ServerSettings
type StepState = State.State
type World = State.World

-- What the server handle starts teleports with: the game's checked tables
export type Settings = {
	shared: Config.Shared,
	server: ServerSettings,
}

-- What a game's callback is handed once a teleport has set a body down
export type Teleported = (character: Character) -> ()

-- What Tread calls on the Promise a game's prestream hook returns, and the hook itself
type Pending = { andThen: (self: Pending, ready: () -> (), rejected: (reason: unknown) -> ()) -> unknown }
type Hook = (player: Player, at: CFrame) -> Pending

type Listener = { callback: Teleported, connected: boolean }

-- The teleports' setup, from the settings at start
type Setup = {
	world: World, -- The server's, which each landing's depenetration runs in
	server: ServerSettings, -- For its prestream hook and its teleport timeout
	wait: number, -- Ticks the timeout lasts at the simulation rate, rounded up
}

local Running: Setup? = nil
local LastTick: number = 0 -- The tick the last run was given, which a teleport's wait counts from
local Serial: number = 0 -- Numbers every teleport, so a replaced one's late finish is told apart from its successor's
local Count: number = 0 -- Teleports pending

-- Each pending teleport by slot: its number, whether its destination is ready, the tick its wait counts from, the
-- character, its step state and connection, and where it goes
local Serials: { [number]: number } = {}
local Ready: { [number]: boolean } = {}
local Called: { [number]: number } = {}
local Movers: { [number]: Character } = {}
local Bodies: { [number]: StepState } = {}
local Links: { [number]: Connection } = {}
local Destinations: { [number]: vector } = {}
local Facings: { [number]: number } = {}

local Listeners: { Listener } = {} -- Replaced whole on a connect or a disconnect, so a landing's walk keeps it

-- A body's state before its landing, put back when the landing throws, and the slot landing, which a warning names
local Before: StepState = State.new()
local CurrentSlot: number = 0

local Failure: string = "" -- What a prestream hook or a stream last threw, with its stack

local Teleport = {}

-- The teleports' setup, erroring from the caller of the member named before Teleport.start has run
local function running(member: string): Setup
	local setup: Setup? = Running
	if not setup then
		error(`{member} ran before the server started`, 3)
	end

	return setup
end

--[[
    Takes the game's checked tables, for the teleport timeout, the
    simulation rate it is counted in and the prestream hook, and the
    server's world each landing's depenetration runs in. It runs once,
    before the first teleport
--]]

function Teleport.start(settings: Settings, world: World)
	if Running then
		error("Teleport.start runs once, and it has already run", 2)
	end

	local server: ServerSettings = settings.server

	Running = {
		world = world,
		server = server,
		wait = math.ceil(server.teleport.timeout * settings.shared.rates.simulation),
	}
end

-- Counts a teleport's destination ready, unless a newer teleport for its slot or a cancel has replaced it
local function settle(slot: number, serial: number)
	if Serials[slot] == serial then
		Ready[slot] = true
	end
end

-- Keeps where a hook's or a stream's error was raised, with its stack, for the warning that follows it
local function keepFailure(message: unknown)
	Failure = debug.traceback(tostring(message), 2)
end

-- Streams the area around a point in for a player, giving up after timeout seconds
local function stream(player: Player, position: Vector3, timeout: number)
	player:RequestStreamAroundAsync(position, timeout)
end

-- Hands the game's prestream hook the destination, and hangs both ways its Promise can settle on it
local function chain(hook: Hook, player: Player, at: CFrame, ready: () -> (), rejected: (reason: unknown) -> ())
	hook(player, at):andThen(ready, rejected)
end

--[[
    A player's destination made ready on a thread of its own: the game's
    prestream hook, whose Promise settles it, or with none the engine's
    stream around it, which gives up after the teleport timeout. A hook
    that throws, a Promise that rejects and a stream that fails are each
    warned, and the destination counts as ready
--]]

local function prepare(setup: Setup, slot: number, serial: number, player: Player, at: CFrame)
	local hook: Hook? = setup.server.prestream
	if hook == nil then
		local timeout: number = setup.server.teleport.timeout
		if not xpcall(stream, keepFailure, player, at.Position, timeout) then
			warn(`Streaming in {player.Name}'s teleport destination failed, so it counts as ready: {Failure}`)
		end

		settle(slot, serial)

		return
	end

	local function ready()
		settle(slot, serial)
	end

	local function rejected(reason: unknown)
		local because: string = tostring(reason)
		warn(`The prestream hook's Promise rejected for {player.Name}'s teleport, so it counts as ready: {because}`)
		settle(slot, serial)
	end

	if not xpcall(chain, keepFailure, hook, player, at, ready, rejected) then
		local name: string = player.Name
		warn(`The prestream hook threw or gave no Promise for {name}'s teleport, so it counts as ready: {Failure}`)
		settle(slot, serial)
	end
end

--[[
    Schedules a character's move to a CFrame, its feet at the position and
    facing along its look, and returns at once. A bot's destination is
    ready now, and a player's once the game's prestream hook resolves, or
    with no hook once the engine has streamed it in while streaming is on,
    or now when it is off. A second teleport for the slot replaces the
    first, its wait counted again from this call
--]]

function Teleport.schedule(character: Character, at: CFrame, state: StepState, connection: Connection)
	local setup: Setup = running("character:teleport")
	if not character._live then
		error("character:teleport ran on a handle already destroyed", 3)
	elseif typeof(at) ~= "CFrame" then
		error(`character:teleport takes where to move the character as a CFrame, not a {typeof(at)}`, 3)
	end

	local position: vector = Engine.toVector(at.Position)
	if
		not (
			math.abs(position.x) <= PLAY_BOUND
			and math.abs(position.z) <= PLAY_BOUND
			and math.abs(position.y) < math.huge
		)
	then
		error(
			`character:teleport takes a finite position inside the {PLAY_BOUND}-stud play bound, not {at.Position}`,
			3
		)
	end

	local look: Vector3 = at.LookVector
	local facing: number = math.atan2(-look.X, -look.Z)

	-- NaN is the one number that differs from itself
	if facing ~= facing then
		error(`character:teleport takes a CFrame whose look is finite, not {look}`, 3)
	end

	local slot: number = character._slot
	if Serials[slot] == nil then
		Count += 1
	end

	Serial += 1
	local serial: number = Serial

	Serials[slot] = serial
	Ready[slot] = false
	Called[slot] = LastTick
	Movers[slot] = character
	Bodies[slot] = state
	Links[slot] = connection
	Destinations[slot] = position
	Facings[slot] = facing

	local player: Player | Bot = character.player
	if typeof(player) == "Instance" and (setup.server.prestream ~= nil or Workspace.StreamingEnabled) then
		task.spawn(prepare, setup, slot, serial, player :: Player, at)
	else
		-- A bot streams nothing in, and with no hook and no streaming there is nothing to wait for
		Ready[slot] = true
	end
end

-- Drops a slot's pending teleport, if it has one
local function forget(slot: number)
	if Serials[slot] == nil then
		return
	end

	Serials[slot] = nil
	Ready[slot] = nil
	Called[slot] = nil
	Movers[slot] = nil
	Bodies[slot] = nil
	Links[slot] = nil
	Destinations[slot] = nil
	Facings[slot] = nil
	Count -= 1
end

--[[
    Drops a slot's pending teleport, for a death, a sleep or a destroy, so
    its body stays where it is and its destination's late finish is
    ignored. A slot with none pending is left as it is
--]]

function Teleport.cancel(slot: number)
	if not Slots.valid(slot) then
		error(`Teleport.cancel takes one of the slot table's slots, not {slot}`, 2)
	end

	forget(slot)
end

-- Runs where a teleport callback's error was raised, so its warning keeps the callback's stack
local function warnTeleported(message: unknown)
	warn(`A teleport callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- Tells every teleport callback of a landing, each under its own xpcall, making no table
local function teleported(character: Character)
	local listeners: { Listener } = Listeners

	for index: number = 1, #listeners do
		local listener: Listener = listeners[index]
		if listener.connected then
			xpcall(listener.callback, warnTeleported, character)
		end
	end
end

--[[
    Sets a body down at its teleport's destination, in this order: the
    position and the facing, no velocity, a slide's cooldown started, the
    mantle ended in the air off the ground with both timers at 0, off any
    ladder or platform, the apex and the last ground at the destination,
    one more epoch, the exact depenetration, the queued commands dropped and
    the range query moved. Then a body no spot frees is reported stuck, and
    every teleport callback hears of the landing
--]]

local function land(
	character: Character,
	state: StepState,
	connection: Connection,
	position: vector,
	facing: number,
	world: World
)
	state.position = position
	state.facing = facing
	state.velocity = vector.zero

	-- A teleport ends a slide as every end but leaving the ground does, so it starts the cooldown
	if state.mode == "Slide" then
		Slide.finish(state, world)
	end

	Mantle.cancel(state)
	state.grounded = false
	state.airTicks = 0
	state.groundTicks = 0
	state.ladder = 0
	state.platform = 0
	state.apex = position.y
	state.groundHeight = position.y
	state.epoch = (state.epoch + 1) % EPOCHS

	local stuck: number? = Collide.depenetrate(state, world, true)
	Commands.drop(connection)
	Range.set(character._slot, state.position, character.player.Name)

	-- Raised once the landing is done, so a report callback that destroys the character leaves nothing half set
	if stuck then
		Reports.fire(character.player, "stuck", stuck)
	end

	teleported(character)
end

-- Runs where a landing raised its error, so its warning keeps the stack
local function warnLanding(message: unknown)
	local reason: string = debug.traceback(tostring(message), 2)
	warn(`The teleport of the character in slot {CurrentSlot} threw, and it was left where it stood: {reason}`)
end

--[[
    Lands, in slot order, every teleport whose destination is ready or
    whose wait has reached the timeout, warning of each that timed out.
    Each lands under its own xpcall, so one whose collision throws is put
    back as it stood, reported as stage and dropped, and the rest still
    land. One scheduled since this tick began waits for the next, and one
    whose character was destroyed is dropped

    @ tick | the simulation tick as the server counts it, unwrapped
--]]

function Teleport.run(tick: number)
	local setup: Setup = running("Teleport.run")
	if not (type(tick) == "number" and tick % 1 == 0 and tick >= LastTick) then
		error(`Teleport.run takes the tick as the server counts it, a whole number from {LastTick} up, not {tick}`, 2)
	end

	LastTick = tick
	if Count == 0 then
		return
	end

	local world: World = setup.world
	local limit: number = setup.wait

	for slot: number = 0, SLOTS - 1 do
		if Serials[slot] == nil or Called[slot] >= tick then
			continue
		end

		local character: Character = Movers[slot]
		if not character._live then
			forget(slot)
			continue
		end

		local ready: boolean = Ready[slot]
		if not ready and tick - Called[slot] < limit then
			continue
		end

		local state: StepState = Bodies[slot]
		local connection: Connection = Links[slot]
		local position: vector = Destinations[slot]
		local facing: number = Facings[slot]
		forget(slot)

		if not ready then
			local name: string = character.player.Name
			local timeout: number = setup.server.teleport.timeout
			warn(`{name}'s teleport destination was not ready after {timeout} s, so the body was set down anyway`)
		end

		State.copy(state, Before)
		CurrentSlot = slot

		if not xpcall(land, warnLanding, character, state, connection, position, facing, world) then
			State.copy(Before, state)
			Reports.fire(character.player, "stage", DECODE)
		end
	end
end

--[[
    Calls back once a teleport has set a character down, with the
    character. Returns the closure that disconnects the callback
--]]

function Teleport.onTeleported(callback: Teleported): () -> ()
	if type(callback) ~= "function" then
		error(`server:onTeleported takes a function, not a {typeof(callback)}`, 2)
	end

	local listener: Listener = { callback = callback, connected = true }
	local listeners: { Listener } = table.clone(Listeners)
	table.insert(listeners, listener)
	Listeners = listeners

	return function ()
		if not listener.connected then
			return
		end

		listener.connected = false

		local kept: { Listener } = table.clone(Listeners)
		local index: number? = table.find(kept, listener)
		if index then
			table.remove(kept, index)
		end

		Listeners = kept
	end
end

return Teleport
