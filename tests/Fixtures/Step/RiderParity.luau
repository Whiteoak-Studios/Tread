--[[
    The riders' fixture: worlds on Lune's pure casts, lifts and bodies on
    them, commands to step them on a tick, and the riders' parity run,
    whose hash Lune and a Studio server must both reach
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Ceiling = require(script.Parent.Ceiling)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Eye = require(ReplicatedStorage.Packages.Tread.Step.Eye)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Platforms = require(ReplicatedStorage.Packages.Tread.Step.Platforms)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local EXPECTED: number = 713853712 -- The hash Lune's own run gives, which every realm's run must match
local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local WRAP: number = 2 ^ 16 -- The ticks world.tick wraps in
local START: number = 65530 -- The run's first tick, a few before the u16 wrap, so the run crosses it
local CLOCK_BEHIND: number = 3 -- How far behind the first tick the run sets the clock, once
local F64_BYTES: number = 8
local LOWEST_BIT: number = 1 -- On byte 0, which holds the lowest mantissa bits of a little-endian f64
local NO_STUCK: number = -1 -- Folded in place of a stuck depth for a step that found the body clear
local FRACTION: number = 0.25 -- How far past each tick the mover is also placed, through the lerp

-- The elevator, the approved example's: a car floor rising and falling on a fixed cycle from the last call
local ELEVATOR: number = 1
local ELEVATOR_BOTTOM: Vector3 = Vector3.new(-15, 1100, 12) -- Its floor's top at the bottom, flush with the floor
local ELEVATOR_FLOOR: Vector3 = Vector3.new(10, 1, 10)
local CYCLE_TICKS: number = 80
local TRAVEL: number = 6 -- Studs it rises, 3 studs a second

-- The mover, a low block beside it that drifts along X and back, its top a step up from the floor
local MOVER: number = 2
local MOVER_START: Vector3 = Vector3.new(-3, 1100, 12) -- Its block's center, the top half a stud over the floor
local MOVER_BLOCK: Vector3 = Vector3.new(6, 1, 6)
local DRIFT_TICKS: number = 160
local DRIFT: number = 4 -- Studs it drifts each way

-- FNV-1a's 32-bit hash. Its prime is 2^24 + 403, so each product is split there and stays exact in a double
local OFFSET_BASIS: number = 2166136261
local PRIME_LOW: number = 403
local PRIME_SHIFT: number = 24
local WORD: number = 2 ^ 32

type Allow = State.Allow
type Command = State.Command
type Part = Geometry.Part
type Platform = State.Platform
type RuleStep = State.RuleStep
type State = State.State
type World = State.World

-- One stretch of the run: ticks of one command's inputs, its presses on its first tick only, and a call of the
-- elevator on that tick when asked
type Leg = {
	ticks: number,
	forward: number,
	right: number,
	yaw: number,
	jump: boolean,
	crouch: boolean,
	sprint: boolean,
	call: boolean,
}

-- Rides the elevator up, walks on it, jumps in it and lands back, sprints off its edge, walks onto the mover and
-- rides it, with the elevator called once the body is off it
local LEGS: { Leg } = {
	{ ticks = 10, forward = 0, right = 0, yaw = 1.7, jump = false, crouch = false, sprint = false, call = false },
	{ ticks = 6, forward = 0.5, right = 0.3, yaw = 1.7, jump = false, crouch = false, sprint = false, call = false },
	{ ticks = 1, forward = 0, right = 0, yaw = 1.7, jump = true, crouch = false, sprint = false, call = false },
	{ ticks = 16, forward = 0, right = 0, yaw = -1.4, jump = false, crouch = false, sprint = false, call = false },
	{ ticks = 12, forward = 1, right = 0, yaw = -1.4, jump = false, crouch = true, sprint = false, call = false },
	{ ticks = 14, forward = 1, right = 0, yaw = -1.6, jump = false, crouch = false, sprint = true, call = true },
	{ ticks = 12, forward = 0, right = 0, yaw = -1.6, jump = false, crouch = false, sprint = false, call = false },
}

local RiderParity = {}

RiderParity.expected = EXPECTED
RiderParity.elevator = ELEVATOR
RiderParity.mover = MOVER

-- A rules function that refuses nothing and caps no speed
local function rules(_: RuleStep, _: Allow): number
	return math.huge
end

--[[
    A server's world over the step's fixture geometry, its ceiling among
    it, and any parts given beside them, at Frontier Zero's simulation
    rate, holding no platform yet
--]]

function RiderParity.world(extra: { Part }?): World
	local parts: { Part } = table.clone(Ceiling.parts)
	for _, part: Part in extra or {} do
		table.insert(parts, part)
	end

	return World.new(Scene.settings, SIMULATION_RATE, Casts(parts), nil, rules, true)
end

--[[
    A lift: the elevator's floor, its top at its position, held at bottom
    until a tick and then rising by rise studs a tick
--]]

function RiderParity.lift(id: number, bottom: Vector3, from: number, rise: number): Platform
	return {
		id = id,
		boxes = { { center = Vector3.new(0, -ELEVATOR_FLOOR.Y / 2, 0), size = ELEVATOR_FLOOR } },
		path = function (tick: number, _: number?): Vector3
			return bottom + Vector3.new(0, math.max(tick - from, 0) * rise, 0)
		end,
	}
end

--[[
    A standing body riding a platform whose top is at its position, at rest
    a skin over it on the tick, offset across its top by x and z
--]]

function RiderParity.standOn(world: World, id: number, tick: number, x: number, z: number): State
	local at: vector = Platforms.at(world, id, tick) :: vector
	local state: State = Scene.state(vector.create(at.x + x, Math.quantize(at.y + Constants.SKIN), at.z + z), true)
	state.platform = id

	return state
end

--[[
    A command with no input and nothing pressed
--]]

function RiderParity.command(): Command
	return {
		number = 0,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

--[[
    Steps a body on an unwrapped tick, the command numbered as that tick
    wraps, as intake numbers a command by its tick. The world's tick wraps
    with it, and its clock stays where it was last set
--]]

function RiderParity.step(state: State, command: Command, world: World, tick: number): (number, number?)
	command.number = tick % WRAP
	world.tick = tick % WRAP

	return Step.advance(state, command, world)
end

--[[
    The elevator of the approved example, its floor's top at its position
--]]

function RiderParity.elevatorPlatform(): Platform
	local half: number = CYCLE_TICKS / 2

	return {
		id = ELEVATOR,
		boxes = { { center = Vector3.new(0, -ELEVATOR_FLOOR.Y / 2, 0), size = ELEVATOR_FLOOR } },
		path = function (tick: number, calledAt: number?): Vector3
			local elapsed: number = (tick - (calledAt or 0)) % CYCLE_TICKS
			local rise: number = math.min(elapsed, CYCLE_TICKS - elapsed) / half

			return ELEVATOR_BOTTOM + Vector3.new(0, TRAVEL * rise, 0)
		end,
	}
end

--[[
    The mover, a block drifting along X and back from where it starts
--]]

function RiderParity.moverPlatform(): Platform
	local half: number = DRIFT_TICKS / 2

	return {
		id = MOVER,
		boxes = { { center = Vector3.zero, size = MOVER_BLOCK } },
		path = function (tick: number, _: number?): Vector3
			local phase: number = tick % DRIFT_TICKS
			local drift: number = math.min(phase, DRIFT_TICKS - phase) / half

			return MOVER_START + Vector3.new(DRIFT * drift, 0, 0)
		end,
	}
end

-- Folds one number's 8 bytes into the hash
local function fold(hash: number, bytes: buffer, value: number): number
	buffer.writef64(bytes, 0, value)

	for index: number = 0, F64_BYTES - 1 do
		local mixed: number = bit32.bxor(hash, buffer.readu8(bytes, index))
		hash = (mixed * PRIME_LOW + bit32.lshift(mixed, PRIME_SHIFT)) % WORD
	end

	return hash
end

local function flipLowestBit(value: number): number
	local bytes: buffer = buffer.create(F64_BYTES)
	buffer.writef64(bytes, 0, value)
	buffer.writeu8(bytes, 0, bit32.bxor(buffer.readu8(bytes, 0), LOWEST_BIT))

	return buffer.readf64(bytes, 0)
end

-- A flag as a number, so it folds like every other value
local function flag(value: boolean): number
	if value then
		return 1
	end

	return 0
end

--[[
    Runs the fixed commands from a body standing on the elevator and gives
    back the hash of every number the run gives, in the order it gives
    them, with each tick's records when trace is given. With flip, the
    first leg's yaw has the lowest bit of its 8 bytes flipped first
--]]

function RiderParity.run(flip: boolean, trace: { { number } }?): number
	local world: World = RiderParity.world()
	Platforms.add(world, RiderParity.elevatorPlatform())
	Platforms.add(world, RiderParity.moverPlatform())
	world.clock = START - CLOCK_BEHIND

	local tick: number = START
	local first: vector = Platforms.at(world, ELEVATOR, tick) :: vector
	local state: State = Scene.state(vector.create(first.x, Math.quantize(first.y + Constants.SKIN), first.z), true)
	state.platform = ELEVATOR

	local order: Command = RiderParity.command()
	local bytes: buffer = buffer.create(F64_BYTES)
	local hash: number = OFFSET_BASIS

	for index: number, leg: Leg in LEGS do
		local yaw: number = leg.yaw
		if flip and index == 1 then
			yaw = flipLowestBit(yaw)
		end

		for count: number = 1, leg.ticks do
			if leg.call and count == 1 then
				Platforms.call(world, ELEVATOR, tick)
			end

			order.forward, order.right, order.yaw = leg.forward, leg.right, yaw
			order.jump, order.crouch, order.sprint = leg.jump, leg.crouch, leg.sprint
			order.pressed.jump = leg.jump and count == 1
			order.pressed.crouch = leg.crouch and count == 1
			order.pressed.sprint = leg.sprint and count == 1

			local landed: number, stuck: number? = RiderParity.step(state, order, world, tick)
			local eye: vector = Eye.clear(state, world)
			local at: vector = state.position
			local velocity: vector = state.velocity
			local elevator: vector = Platforms.at(world, ELEVATOR, tick) :: vector
			local mover: vector = Platforms.at(world, MOVER, tick + FRACTION) :: vector

			local values: { number } = {
				Platforms.tick(world),
				landed,
				stuck or NO_STUCK,
				at.x,
				at.y,
				at.z,
				velocity.x,
				velocity.y,
				velocity.z,
				state.facing,
				state.platform,
				flag(state.grounded),
				flag(state.posture == "Crouch"),
				eye.x,
				eye.y,
				eye.z,
				elevator.x,
				elevator.y,
				elevator.z,
				mover.x,
				mover.y,
				mover.z,
				Math.sin(yaw),
				Math.cos(yaw),
			}

			for _, value: number in values do
				hash = fold(hash, bytes, value)
			end

			if trace then
				table.insert(trace, values)
			end

			tick += 1
		end
	end

	return hash
end

return RiderParity
