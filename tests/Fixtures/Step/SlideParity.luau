--[[
    The crouch slide's parity run: fixed commands through Step.advance on
    the slide fixture's floor, every number they give folded by its 8 bytes
    into one hash, which every realm's run must reach
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Slides = require(script.Parent.Slides)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local EXPECTED: number = 3577409341 -- The hash Lune's own run gives, which every realm's run must match
local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
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
	jump: boolean,
	crouch: boolean,
	sprint: boolean,
}

-- A sprint, a slide steered off its line at yaws that are no quarter turn, a jump out of it and its landing, a
-- crouched walk inside the cooldown, a stand into a sprint, and a second slide run out to its end
local LEGS: { Leg } = {
	{ ticks = 4, forward = 1, right = 0, yaw = 0.2, jump = false, crouch = false, sprint = true },
	{ ticks = 1, forward = 1, right = 0, yaw = 0.2, jump = false, crouch = true, sprint = false },
	{ ticks = 12, forward = 1, right = 0.5, yaw = 0.6, jump = false, crouch = true, sprint = false },
	{ ticks = 1, forward = 1, right = 0.5, yaw = 0.6, jump = true, crouch = true, sprint = false },
	{ ticks = 14, forward = 1, right = 0, yaw = 0.6, jump = false, crouch = true, sprint = false },
	{ ticks = 20, forward = 1, right = 0, yaw = 1.1, jump = false, crouch = true, sprint = false },
	{ ticks = 6, forward = 1, right = 0, yaw = 1.1, jump = false, crouch = false, sprint = true },
	{ ticks = 1, forward = 1, right = 0, yaw = 1.1, jump = false, crouch = true, sprint = false },
	{ ticks = 44, forward = 0.7, right = -0.7, yaw = 1.4, jump = false, crouch = true, sprint = false },
}

local SlideParity = {}

SlideParity.expected = EXPECTED

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

-- A rules function that refuses nothing and caps no speed
local function free(_: RuleStep, _: Allow): number
	return math.huge
end

--[[
    Runs the fixed commands from the fixed start and gives back the hash of
    every number the run gives, in the order it gives them, and how many of
    its ticks ended in a slide. With flip, the first leg's yaw has the
    lowest bit of its 8 bytes flipped first
--]]

function SlideParity.run(flip: boolean): (number, number)
	local world: World = World.new(Slides.settings(), SIMULATION_RATE, Casts(Slides.parts), nil, free, true)
	local state: State = Slides.state(vector.create(0, Slides.resting, 100), true)
	local order: Command = Slides.command()
	local bytes: buffer = buffer.create(F64_BYTES)
	local hash: number = OFFSET_BASIS
	local number: number = 1
	local slid: number = 0

	for index: number, leg: Leg in LEGS do
		local yaw: number = leg.yaw
		if flip and index == 1 then
			yaw = flipLowestBit(yaw)
		end

		for tick: number = 1, leg.ticks do
			order.number = number
			order.forward, order.right, order.yaw = leg.forward, leg.right, yaw
			order.jump, order.crouch, order.sprint = leg.jump, leg.crouch, leg.sprint
			order.pressed.jump = leg.jump and tick == 1
			order.pressed.crouch = leg.crouch and tick == 1
			order.pressed.sprint = leg.sprint and tick == 1

			world.tick = number
			local landed: number, stuck: number? = Step.advance(state, order, world)
			local at: vector = state.position
			local velocity: vector = state.velocity

			if state.mode == "Slide" then
				slid += 1
			end

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
					state.eyeHeight,
					state.apex,
					state.groundHeight,
					state.groundTicks,
					state.airTicks,
					state.slideCooldown,
					state.jumps,
					state.lands,
					flag(state.grounded),
					flag(state.mode == "Slide"),
					flag(state.posture == "Crouch"),
					Math.sin(yaw),
					Math.cos(yaw),
				}
			do
				hash = fold(hash, bytes, value)
			end

			number += 1
		end
	end

	return hash, slid
end

return SlideParity
