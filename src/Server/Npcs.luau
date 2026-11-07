--[[
    The server's NPCs: bodies with no owning client, each in a slot of its
    own, stepped through the shared step from the last command the server
    issued it, in slot order in a tick stage of their own
--]]

--!strict
--!native
local Npc = {}
Npc.__index = Npc

local Collide = require(script.Parent.Parent.Step.Collide)
local Constants = require(script.Parent.Parent.Constants)
local Math = require(script.Parent.Parent.Step.Math)
local Range = require(script.Parent.Range)
local Reports = require(script.Parent.Reports)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local Step = require(script.Parent.Parent.Step)

local PLAY_BOUND: number = Constants.PLAY_BOUND
local LAST_TICK: number = 2 ^ 16 - 1 -- The top of the u16 a tick and a command number ride in, wrapped by the tick loop
local STAGE: string = "npcs" -- The tick stage the NPCs step in, which a body's failed step is reported under

type Command = State.Command
type Pressed = State.Pressed
type State = State.State
type Values = State.Values
type World = State.World

-- A command as the server issues it to an NPC: a step command's inputs, whose presses the NPC derives itself
export type Order = {
	forward: number, -- The move axes, each -1 to 1
	right: number,
	jump: boolean, -- The button levels
	crouch: boolean,
	sprint: boolean,
	aim: boolean,
	yaw: number, -- The base look, radians
	pitch: number,
	lean: number, -- Degrees
	headYaw: number, -- The head offset, degrees
	headPitch: number,
	fields: Values, -- The game's declared command fields
}

-- What the server handle is told of each landing that counted, with the speed the NPC met the ground at
export type Landed = (npc: Npc, speed: number) -> ()

type Fields = {
	slot: number, -- Its slot and that slot's generation, for the whole of its life
	generation: number,
	_state: State,
	_command: Command, -- What it steps from, its presses kept until a step applies them
	_awake: boolean,
	_live: boolean, -- Until destroy
}

local Bodies: { Npc } = {} -- Every live NPC, in slot order
local Active: World? = nil -- The server's world the NPCs step in, once Npcs.start has run
local OnLanded: Landed? = nil
local Before: State = State.new() -- A body's state before its step, put back when the step throws
local Current: number = 0 -- The slot being stepped, which a failed step's warning names

local Npcs = {}

-- A value less itself is 0 only when the value is finite
local function finite(value: number): boolean
	return value - value == 0
end

-- The world the NPCs step in, erroring from the caller of the member named when Npcs.start has not run
local function active(member: string): World
	local world: World? = Active
	if not world then
		error(`{member} ran before Npcs.start handed it the server's world`, 3)
	end

	return world
end

--[[
    Starts the NPCs on the server's world, the one World.new built for the
    players, and the callback each landing that counted is handed to. It
    runs once, before the first NPC is made
--]]

function Npcs.start(world: World, landed: Landed)
	if Active then
		error("Npcs.start runs once, and it has already run", 2)
	elseif type(world) ~= "table" then
		error(`Npcs.start takes the server's World, not a {typeof(world)}`, 2)
	elseif type(landed) ~= "function" then
		error(`Npcs.start takes the landing callback as a function, not a {typeof(landed)}`, 2)
	end

	Active = world
	OnLanded = landed
end

-- A command with no input, looking along facing, its presses all off
local function newCommand(facing: number): Command
	return {
		number = 0,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = facing,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

-- Puts an NPC in the stepping order, before the first whose slot is higher
local function insert(npc: Npc)
	local index: number = #Bodies + 1

	for at: number, other: Npc in Bodies do
		if other.slot > npc.slot then
			index = at
			break
		end
	end

	table.insert(Bodies, index, npc)
end

--[[
    Makes an NPC in a slot of its own, its feet at position and facing
    along facing, awake on a command with no input. Its exact depenetration
    runs as at any spawn, a body no spot frees is reported stuck, and the
    range query holds it where it ends
--]]

function Npcs.create(position: vector, facing: number): Npc
	local world: World = active("Npcs.create")
	if type(position) ~= "vector" then
		error(`Npcs.create takes its position as a vector, not a {typeof(position)}`, 2)
	elseif not (math.abs(position.x) <= PLAY_BOUND and math.abs(position.z) <= PLAY_BOUND and finite(position.y)) then
		error(`Npcs.create takes a finite position inside the {PLAY_BOUND}-stud play bound, not {position}`, 2)
	elseif type(facing) ~= "number" or not finite(facing) then
		error(`Npcs.create takes a finite facing in radians, not {facing}`, 2)
	end

	local state: State = State.new()
	state.position = position
	state.facing = facing
	state.apex = position.y
	state.groundHeight = position.y
	state.eyeHeight = Math.quantizeEye(world.settings.eyeStanding)
	state.npc = true

	-- Before the slot is taken, so a game collision function that throws here holds no slot
	local stuck: number? = Collide.depenetrate(state, world, true)

	local slot: number?, generation: number? = Slots.take("Npc")
	if slot == nil or generation == nil then
		error("Npcs.create found no slot free for an NPC", 2)
	end

	local npc: Npc = setmetatable({
		slot = slot,
		generation = generation,
		_state = state,
		_command = newCommand(facing),
		_awake = true,
		_live = true,
	}, Npc)

	Range.set(slot, state.position)
	insert(npc)

	if stuck then
		Reports.fire(nil, "stuck", stuck)
	end

	return npc
end

-- Errors from the caller of the member named when the NPC is already destroyed
local function live(npc: Npc, member: string)
	if not npc._live then
		error(`{member} ran on an NPC already destroyed`, 3)
	end
end

-- Errors from the caller of npc:command naming the first part of a command it cannot hold
local function check(command: Order)
	if type(command) ~= "table" then
		error(`npc:command takes a command table, not a {typeof(command)}`, 3)
	elseif type(command.forward) ~= "number" or type(command.right) ~= "number" then
		error("npc:command takes the move axes as numbers", 3)
	elseif type(command.yaw) ~= "number" or type(command.pitch) ~= "number" or type(command.lean) ~= "number" then
		error("npc:command takes the yaw, pitch and lean as numbers", 3)
	elseif type(command.headYaw) ~= "number" or type(command.headPitch) ~= "number" then
		error("npc:command takes the head offset's yaw and pitch as numbers", 3)
	elseif type(command.jump) ~= "boolean" or type(command.crouch) ~= "boolean" then
		error("npc:command takes the jump and crouch levels as booleans", 3)
	elseif type(command.sprint) ~= "boolean" or type(command.aim) ~= "boolean" then
		error("npc:command takes the sprint and aim levels as booleans", 3)
	elseif type(command.fields) ~= "table" then
		error(`npc:command takes the game's declared fields as a table, not a {typeof(command.fields)}`, 3)
	end
end

--[[
    Issues the command the NPC steps from every tick while awake. Its levels
    repeat each tick, and a level held here and not in the command before
    is a press, kept until a step applies it once. The game's declared
    fields are held as given
--]]

function Npc.command(self: Self, command: Order)
	live(self, "npc:command")
	check(command)

	local own: Command = self._command
	local pressed: Pressed = own.pressed
	pressed.jump = pressed.jump or (command.jump and not own.jump)
	pressed.crouch = pressed.crouch or (command.crouch and not own.crouch)
	pressed.sprint = pressed.sprint or (command.sprint and not own.sprint)
	pressed.aim = pressed.aim or (command.aim and not own.aim)

	own.forward = command.forward
	own.right = command.right
	own.jump = command.jump
	own.crouch = command.crouch
	own.sprint = command.sprint
	own.aim = command.aim
	own.yaw = command.yaw
	own.pitch = command.pitch
	own.lean = command.lean
	own.headYaw = command.headYaw
	own.headPitch = command.headPitch

	-- Whiteoak TODO: a carried or dropped field repeats every tick as a held one does; clearing it after the step
	-- that applies it needs the command declarations from the server's start, once a game sends a press there
	own.fields = command.fields
end

--[[
    Wakes the NPC or idles it. An idle NPC takes no step and keeps its
    state, and its presses wait for the step that wakes it
--]]

function Npc.setAwake(self: Self, awake: boolean)
	live(self, "npc:setAwake")
	if type(awake) ~= "boolean" then
		error(`npc:setAwake takes a boolean, not a {typeof(awake)}`, 2)
	end

	self._awake = awake
end

--[[
    Whether the NPC steps each tick, for the stages that keep a stepped
    body's history and count the awake NPCs
--]]

function Npc.isAwake(self: Self): boolean
	return self._awake
end

--[[
    The step's own state for the NPC, the same table from tick to tick,
    which each step moves in place
--]]

function Npc.getState(self: Self): State
	return self._state
end

--[[
    Ends the NPC: it steps no more, leaves the range query, and its slot
    goes back to the slot table
--]]

function Npc.destroy(self: Self)
	live(self, "npc:destroy")
	self._live = false

	local index: number? = table.find(Bodies, self)
	if index then
		table.remove(Bodies, index)
	end

	Range.remove(self.slot)
	Slots.release(self.slot)
end

-- Runs where the step's error was raised, so its warning keeps the stack
local function warnFailure(message: unknown)
	local reason: string = debug.traceback(tostring(message), 2)
	warn(`The step of the NPC in slot {Current} threw, and it was left unstepped for the tick: {reason}`)
end

--[[
    One NPC's step from its command, numbered by the tick, under its own
    xpcall. A step that throws puts the body back as it was, keeps its
    presses for the next step and is reported; one that runs clears them,
    moves the range query, and reports its stuck depth and its landing
--]]

local function advance(npc: Npc, world: World, tick: number)
	local state: State = npc._state
	local command: Command = npc._command
	command.number = tick

	State.copy(state, Before)
	Current = npc.slot

	local stepped: boolean, landed: number?, stuck: number? = xpcall(Step.advance, warnFailure, state, command, world)
	if not stepped then
		State.copy(Before, state)
		Reports.fire(nil, "stage", STAGE)

		return
	end

	local pressed: Pressed = command.pressed
	pressed.jump = false
	pressed.crouch = false
	pressed.sprint = false
	pressed.aim = false

	Range.set(npc.slot, state.position)

	if stuck then
		Reports.fire(nil, "stuck", stuck)
	end

	local onLanded: Landed? = OnLanded
	if onLanded and landed and landed > 0 then
		onLanded(npc, landed)
	end
end

--[[
    The npcs stage of one tick, which runs after every player has stepped:
    each awake NPC in slot order, each under its own xpcall, so one whose
    game rules throw is left unstepped and the rest still step
--]]

function Npcs.step(tick: number)
	local world: World = active("Npcs.step")
	if type(tick) ~= "number" or tick % 1 ~= 0 or tick < 0 or tick > LAST_TICK then
		error(`Npcs.step takes the tick as a whole number of 0 or more, at most {LAST_TICK}, not {tick}`, 2)
	end

	world.tick = tick

	-- A copy, so a callback that makes an NPC mid-stage waits for the next tick and one it destroys is skipped
	for _, npc: Npc in table.clone(Bodies) do
		if npc._live and npc._awake then
			advance(npc, world, tick)
		end
	end
end

--[[
    Visits every live NPC, awake or idle, in slot order. A copy is walked,
    so a visit may make or destroy one
--]]

function Npcs.each(visit: (npc: Npc) -> ())
	if type(visit) ~= "function" then
		error(`Npcs.each takes a function, not a {typeof(visit)}`, 2)
	end

	for _, npc: Npc in table.clone(Bodies) do
		if npc._live then
			visit(npc)
		end
	end
end

export type Npc = Self
type Self = typeof(setmetatable({} :: Fields, Npc))

return Npcs
