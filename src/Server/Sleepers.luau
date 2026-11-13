--[[
    The server's sleepers and bodies: each one's slot and lying state, and
    the fall a sleeper's latest move takes, along which its lying hit shapes
    are placed for a render time
--]]

--!strict
--!native
local Config = require(script.Parent.Parent.Config)
local Constants = require(script.Parent.Parent.Constants)
local History = require(script.Parent.History)
local Math = require(script.Parent.Parent.Step.Math)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local World = require(script.Parent.Parent.Step.World)

local PLAY_BOUND: number = Constants.PLAY_BOUND
local SLOTS: number = Constants.SLOTS
local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi) -- Steps a radian of yaw, a turn being the u16's wrap
local RIG: Slots.Rig = "A" -- The rig mode every body is drawn with, the one the first release has

type Kind = "Sleeper" | "Body"
type Lying = History.Lying
type Sample = History.Sample
type Shared = Config.Shared
type State = State.State
type World = State.World

local Kinds: { [number]: Kind } = {} -- Each slot this module holds, a sleeper's or a body's
local States: { [number]: State } = {} -- Each held slot's lying state, create's own or the one a sleep adopted
local Built: { [number]: State } = {} -- The state create builds for a slot, once, and reuses for every later life there
local From: { [number]: vector } = {} -- Where a sleeper's latest move falls from; its state's position is where to
local FromYaw: { [number]: number } = {} -- Its yaw there in radians, turning on the shortest arc to its state's facing
local MoveTick: { [number]: number } = {} -- The relay tick that move's fall starts on, unwrapped

local Entry: Slots.Entry = { kind = "Sleeper", rig = RIG } -- The entry each change hands Slots.setEntry, which copies it
local Fresh: State = State.new() -- Every field a new life starts with, which a reused state is reset to

-- What start reads
local ServerWorld: World? = nil -- The server's world, whose gravity by tick every fall is placed under
local SimulationRate: number = 0 -- Hz, the rate the world's gravity changes count ticks at
local RelayRate: number = 0 -- Hz, the rate render times count ticks at
local EyeHeight: number = 0 -- The Downed eye height above the feet, at OwnerState's 1/32 stud
local Started: boolean = false

local Sleepers = {}

--[[
    Takes the server's world, whose gravity by tick a moved sleeper falls
    under, the shared table's rates, which render times and the world's
    changes count ticks in, and its Downed eye height. It runs once, before
    any other call, on a table Config has checked
--]]

function Sleepers.start(shared: Shared, world: World)
	if Started then
		error("Sleepers.start runs once, and it has already run", 2)
	elseif type(world) ~= "table" then
		error(`Sleepers.start takes the server's World, not a {typeof(world)}`, 2)
	end

	ServerWorld = world
	SimulationRate = shared.rates.simulation
	RelayRate = shared.rates.relay
	EyeHeight = Math.quantizeEye(shared.step.eyeDowned)
	Started = true
end

-- A value less itself is 0 only when the value is finite
local function finite(value: number): boolean
	return type(value) == "number" and value - value == 0
end

local function isWhole(value: number): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

-- Errors from the caller of the member named unless the place is inside the play bound and the yaw finite
local function checkPlace(member: string, position: vector, yaw: number)
	if type(position) ~= "vector" then
		error(`Sleepers.{member} takes its position as a vector, not a {typeof(position)}`, 3)
	elseif not (math.abs(position.x) <= PLAY_BOUND and math.abs(position.z) <= PLAY_BOUND and finite(position.y)) then
		error(`Sleepers.{member} takes a finite position inside the {PLAY_BOUND}-stud play bound, not {position}`, 3)
	elseif not finite(yaw) then
		error(`Sleepers.{member} takes a finite yaw in radians, not {yaw}`, 3)
	end
end

-- Errors from the caller of the member named unless this module holds the slot, as the one kind given if any
local function check(slot: number, member: string, only: Kind?)
	if not Started then
		error(`Sleepers.{member} ran before Sleepers.start`, 3)
	elseif not Slots.valid(slot) then
		error(`Sleepers.{member} takes a slot from 0 to {SLOTS - 1}, not {slot}`, 3)
	end

	local kind: Kind? = Kinds[slot]
	if kind == nil then
		error(`Sleepers.{member} takes a sleeper's or a body's slot, and slot {slot} holds neither`, 3)
	elseif only and kind ~= only then
		error(`Sleepers.{member} takes a {only}'s slot, and slot {slot} holds a {kind}`, 3)
	end
end

-- Errors from the caller of the member named unless the tick is a whole relay tick
local function checkTick(member: string, tick: number)
	if not isWhole(tick) then
		error(`Sleepers.{member} takes the relay tick as a whole number of 0 or more, not {tick}`, 3)
	end
end

--[[
    Lays a state down where it is told: Downed in Ground, grounded and at
    rest, with no lean, sprint or aim, walking, on no platform or ladder,
    holding no item. Its epoch and the game's blocks stay as they are
--]]

local function lie(state: State, position: vector, yaw: number)
	state.position = position
	state.velocity = vector.zero
	state.facing = yaw
	state.mode = "Ground"
	state.posture = "Downed"
	state.sprint = false
	state.aim = false
	state.platform = 0
	state.moveMode = "Walk"
	state.grounded = true
	state.lean = 0
	state.eyeHeight = EyeHeight
	state.apex = position.y
	state.groundHeight = position.y
	state.mantleTicks = 0
	state.mantleRise = 0
	state.ladder = 0

	table.clear(state.held)
end

-- Holds a slot as a sleeper or a body lying where its state lies, with no move to fall along yet
local function hold(slot: number, kind: Kind, state: State)
	Kinds[slot] = kind
	States[slot] = state
	From[slot] = state.position
	FromYaw[slot] = state.facing
	MoveTick[slot] = 0
end

local function forget(slot: number)
	Kinds[slot] = nil
	States[slot] = nil
	From[slot] = nil
	FromYaw[slot] = nil
	MoveTick[slot] = nil
end

--[[
    Where a sleeper lies at a time in relay ticks, and its yaw: where its
    latest move falls from before that move's tick, along the fall from
    then under the gravity the world gives that time, and where the move
    put it once the fall is done
--]]

local function placeAt(slot: number, time: number): (vector, number)
	local state: State = States[slot]
	local from: vector = From[slot]
	local fromYaw: number = FromYaw[slot]

	local elapsed: number = (time - MoveTick[slot]) / RelayRate
	if elapsed < 0 then
		return from, fromYaw
	end

	local world: World? = ServerWorld
	if not world then
		error("Sleepers placed a fall before Sleepers.start")
	end

	-- The time counted in simulation ticks, as the world's gravity changes are
	local gravity: number = World.gravityFor(world, time * SimulationRate / RelayRate)
	local position: vector, fraction: number = Math.fall(from, state.position, gravity, elapsed)
	local start: number = fromYaw * YAW_SCALE
	local turn: number = Sequence.difference(state.facing * YAW_SCALE, start)

	return position, Math.lerp(start, start + turn, fraction) / YAW_SCALE
end

--[[
    Makes a sleeper or a body in a slot of its own, lying at position along
    yaw, and returns the slot, its generation and its lying state, which
    the relay reads. A sleeper past the sleepers' share gets nil, and a body
    that finds no slot free errors naming the reserve

    @ yaw | radians, the step's facing
--]]

function Sleepers.create(kind: Kind, position: vector, yaw: number): (number?, number?, State?)
	if not Started then
		error("Sleepers.create ran before Sleepers.start", 2)
	elseif kind ~= "Sleeper" and kind ~= "Body" then
		error(`Sleepers.create takes a Sleeper or a Body, not {kind}`, 2)
	end

	checkPlace("create", position, yaw)

	local slot: number?, generation: number? = Slots.take(kind)
	if slot == nil or generation == nil then
		return nil, nil, nil
	end

	local state: State = Built[slot] or State.new()
	Built[slot] = state

	State.copy(Fresh, state)
	lie(state, position, yaw)
	hold(slot, kind, state)

	Entry.kind = kind
	Entry.rig = RIG
	Slots.setEntry(slot, Entry)

	return slot, generation, state
end

--[[
    Turns a character's slot sleeper, keeping the slot, its generation and
    its rig, and lays the character's own state down in place as the
    sleeper's. Past the sleepers' share nothing changes and this is false
--]]

function Sleepers.adopt(slot: number, state: State): boolean
	if not Started then
		error("Sleepers.adopt ran before Sleepers.start", 2)
	elseif not Slots.valid(slot) then
		error(`Sleepers.adopt takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	elseif type(state) ~= "table" then
		error(`Sleepers.adopt takes the character's State, not a {typeof(state)}`, 2)
	end

	local _, entry: Slots.Entry? = Slots.get(slot)
	if entry == nil then
		error(`Sleepers.adopt takes a character's slot, and slot {slot} has no entry`, 2)
	elseif entry.kind ~= "Player" then
		error(`Sleepers.adopt takes a character's slot, and slot {slot} holds a {entry.kind}`, 2)
	end

	Entry.kind = "Sleeper"
	Entry.rig = entry.rig
	if not Slots.setEntry(slot, Entry) then
		return false
	end

	lie(state, state.position, state.facing)
	hold(slot, "Sleeper", state)

	return true
end

--[[
    Moves a sleeper to lie at position along yaw, keeping its slot and
    generation. Its fall starts on the tick from where the fall before it
    has it then, so a move during a fall never jumps, and only the latest
    move is kept. The lying state takes the new place at once

    @ tick | the relay tick the move's reveal first rides, unwrapped, never before the last move's
--]]

function Sleepers.move(slot: number, position: vector, yaw: number, tick: number)
	check(slot, "move", "Sleeper")
	checkPlace("move", position, yaw)
	checkTick("move", tick)

	local last: number = MoveTick[slot]
	if tick < last then
		error(`Sleepers.move took tick {tick} for slot {slot}, whose last move falls from tick {last}`, 2)
	end

	-- Whiteoak TODO: a move during a fall starts from where that fall has it under the gravity the world holds for the
	-- move's tick when the move is made, so a setGravity later in the same frame that applies from that tick leaves
	-- the new fall starting where the old value put it; placing the start again when such a change is set fixes it
	local at: vector, atYaw: number = placeAt(slot, tick)
	From[slot] = at
	FromYaw[slot] = atYaw
	MoveTick[slot] = tick

	lie(States[slot], position, yaw)
end

--[[
    A sleeper's lying hit shapes at a render time: at its latest move's old
    place before the move's tick, along the fall through Math.fall under
    the gravity the world gives the render time during it, and at the new
    place after. A move whose new place is not below the old lands on its
    tick. The Sample is the slot's own table, which the next read for it
    rewrites

    @ renderTime | relay ticks as the server counts them, unwrapped, with their fraction
--]]

function Sleepers.sampleAt(slot: number, renderTime: number): Sample
	check(slot, "sampleAt", "Sleeper")
	if not finite(renderTime) then
		error(`Sleepers.sampleAt takes the render time as a finite number of relay ticks, not {renderTime}`, 2)
	end

	local position: vector, yaw: number = placeAt(slot, renderTime)

	return History.lying(slot, position, yaw, States[slot].epoch)
end

--[[
    Forgets a sleeper as it wakes, keeping its slot, and returns the lying
    sample a woken character's history is seeded with: its state's epoch
    and where it lies at the tick, along its fall if it is falling, where
    its state is laid too, so the woken body stands where it was drawn
--]]

function Sleepers.wake(slot: number, tick: number): Lying
	check(slot, "wake", "Sleeper")
	checkTick("wake", tick)

	local state: State = States[slot]
	local position: vector, yaw: number = placeAt(slot, tick)

	lie(state, position, yaw)
	forget(slot)

	return { epoch = state.epoch, position = position, platform = state.platform, yaw = yaw }
end

--[[
    Forgets a sleeper or a body and releases its slot, for a kill, a
    destroy or a body's removal
--]]

function Sleepers.remove(slot: number)
	check(slot, "remove", nil)

	forget(slot)
	Slots.release(slot)
end

return Sleepers
