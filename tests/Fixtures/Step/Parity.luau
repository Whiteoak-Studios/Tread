--[[
    The step's parity run: fixed commands through Step.advance and Eye.clear
    on Lune's pure casts, every number they give folded by its 8 bytes into
    one hash, which Lune and a Studio server must both reach
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Ceiling = require(script.Parent.Ceiling)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Eye = require(ReplicatedStorage.Packages.Tread.Step.Eye)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local EXPECTED: number = 1291920442 -- The hash Lune's own run gives, which every realm's run must match
local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local START: vector = vector.create(-20, Geometry.floor + Constants.SKIN, -12)
local F64_BYTES: number = 8
local LOWEST_BIT: number = 1 -- On byte 0, which holds the lowest mantissa bits of a little-endian f64
local NO_STUCK: number = -1 -- Folded in place of a stuck depth for a step that found the body clear

-- FNV-1a's 32-bit hash. Its prime is 2^24 + 403, so each product is split there and stays exact in a double
local OFFSET_BASIS: number = 2166136261
local PRIME_LOW: number = 403
local PRIME_SHIFT: number = 24
local WORD: number = 2 ^ 32

type Allow = State.Allow
type Command = State.Command
type RuleStep = State.RuleStep
type State = State.State
type World = State.World

-- One stretch of the run: ticks of one command's inputs, its presses on its first tick only
type Leg = {
	ticks: number,
	forward: number,
	right: number,
	yaw: number,
	pitch: number,
	lean: number,
	headYaw: number,
	headPitch: number,
	jump: boolean,
	crouch: boolean,
	sprint: boolean,
}

-- Walks, a sprint under the rules' cap, a jump with its air control and landing, a crouch with a lean, a stand
-- with a head offset and a long sprinting diagonal, at yaws that are no quarter turn
local LEGS: { Leg } = {
	{
		ticks = 8,
		forward = 1,
		right = 0,
		yaw = 0.3,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		jump = false,
		crouch = false,
		sprint = false,
	},
	{
		ticks = 6,
		forward = 1,
		right = 0.5,
		yaw = 1.9,
		pitch = 0.2,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		jump = false,
		crouch = false,
		sprint = true,
	},
	{
		ticks = 1,
		forward = 1,
		right = 0,
		yaw = 1.9,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		jump = true,
		crouch = false,
		sprint = true,
	},
	{
		ticks = 16,
		forward = 0.6,
		right = -0.8,
		yaw = 4.4,
		pitch = -0.3,
		lean = 13,
		headYaw = 0,
		headPitch = 0,
		jump = true,
		crouch = false,
		sprint = false,
	},
	{
		ticks = 6,
		forward = -1,
		right = 0,
		yaw = 2.7,
		pitch = 0,
		lean = -7,
		headYaw = 0,
		headPitch = 0,
		jump = false,
		crouch = true,
		sprint = false,
	},
	{
		ticks = 4,
		forward = 0,
		right = 1,
		yaw = 2.7,
		pitch = 0.5,
		lean = -7,
		headYaw = 40,
		headPitch = -12,
		jump = false,
		crouch = false,
		sprint = false,
	},
	{
		ticks = 12,
		forward = 1,
		right = 1,
		yaw = 5.6,
		pitch = 0,
		lean = 20,
		headYaw = 0,
		headPitch = 0,
		jump = false,
		crouch = false,
		sprint = true,
	},
}

local Parity = {}

Parity.expected = EXPECTED

-- A rules function that caps a sprint at a speed between the walk's and the sprint's
local function rules(step: RuleStep, _: Allow): number
	if step.command.sprint then
		return Scene.settings.sprint - Scene.settings.walk / 3
	end

	return math.huge
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
    Runs the fixed commands from the fixed start and gives back the hash of
    every number the run gives, in the order it gives them. With flip, the
    first leg's yaw has the lowest bit of its 8 bytes flipped first
--]]

function Parity.run(flip: boolean): number
	local world: World = World.new(Scene.settings, SIMULATION_RATE, Casts(Ceiling.parts), nil, rules, true)
	local state: State = Scene.state(START, true)
	local bytes: buffer = buffer.create(F64_BYTES)
	local hash: number = OFFSET_BASIS
	local number: number = 1

	local order: Command = {
		number = number,
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

	for index: number, leg: Leg in LEGS do
		local yaw: number = leg.yaw
		if flip and index == 1 then
			yaw = flipLowestBit(yaw)
		end

		for tick: number = 1, leg.ticks do
			order.number = number
			order.forward, order.right = leg.forward, leg.right
			order.yaw, order.pitch = yaw, leg.pitch
			order.lean, order.headYaw, order.headPitch = leg.lean, leg.headYaw, leg.headPitch
			order.jump, order.crouch, order.sprint = leg.jump, leg.crouch, leg.sprint
			order.pressed.jump = leg.jump and tick == 1
			order.pressed.crouch = leg.crouch and tick == 1
			order.pressed.sprint = leg.sprint and tick == 1

			world.tick = number
			local landed: number, stuck: number? = Step.advance(state, order, world)
			local eye: vector = Eye.clear(state, world)
			local at: vector = state.position
			local velocity: vector = state.velocity

			for _, value: number in
				{
					landed,
					stuck or NO_STUCK,
					at.x,
					at.y,
					at.z,
					velocity.x,
					velocity.y,
					velocity.z,
					state.facing,
					state.lean,
					state.eyeHeight,
					state.apex,
					state.groundHeight,
					state.groundTicks,
					state.airTicks,
					state.jumps,
					state.lands,
					flag(state.heavy),
					flag(state.grounded),
					flag(state.posture == "Crouch"),
					order.headYaw,
					order.headPitch,
					eye.x,
					eye.y,
					eye.z,
					Math.sin(yaw),
					Math.cos(yaw),
				}
			do
				hash = fold(hash, bytes, value)
			end

			number += 1
		end
	end

	return hash
end

return Parity
