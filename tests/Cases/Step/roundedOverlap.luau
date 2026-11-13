--[[
    In a packed crowd, a walk a skin short of one hull rounds under 1/1024
    stud into a second's face, and the second's next step parts the pair at
    the smallest depenetration spot, with no stuck report and no overlap
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local HULLS: string = "src/Step/Hulls.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"

local FEET: number = 0.51953125 -- Where the ground snap rests feet on the floor below, on the quantum
local FIRST: number = 2833 -- The first command's number, off every tenth, so no step runs the exact overlap check

-- The floor every body stands on, its top at 0.5
local FLOOR: { [string]: any } = {
	name = "Floor",
	center = vector.create(0, -0.5, 0),
	size = vector.create(40, 2, 40),
	tilt = 0,
}

-- A body that walks: its feet and velocity, and the yaw of its command each tick
type Walker = {
	feet: vector,
	velocity: vector,
	yaws: { number },
}

-- Stepped in this order each tick
local WALKERS: { Walker } = {
	-- Along -Z with a sliver of +X, its stop a skin short of the second leaving it a fraction of a quantum short of
	-- the third's face, which the rounding crosses
	{
		feet = vector.create(0.107421875, FEET, -0.095703125),
		velocity = vector.create(0.09375, 0, -10),
		yaws = { -0.0098154821262129727, -0.0097904634986378421 },
	},

	-- Ahead of the first along -Z, walking away from it
	{
		feet = vector.create(-0.19921875, FEET, -3.197265625),
		velocity = vector.zero,
		yaws = { -2.3922661546578468, -2.3922661546578468 },
	},

	-- The one the first rounds into, walking back toward it
	{
		feet = vector.create(2.890625, FEET, 1.6796875),
		velocity = vector.zero,
		yaws = { 0.90902773283806459, 0.90902773283806459 },
	},
}

-- Bodies standing still around the pair, which take every spot a sixteenth of a hull width or more from the third
local CROWD: { vector } = {
	vector.create(5.69140625, FEET, 1.681640625),
	vector.create(3.662109375, 0.5, -1.1171875),
	vector.create(3.392578125, FEET, 4.482421875),
	vector.create(-2.197265625, FEET, 5.203125),
	vector.create(-2.7109375, FEET, -0.396484375),
}

-- Where the first walker's first step ends, its hull inside the third's
local MERGED: vector = vector.create(0.111328125, FEET, -0.396484375)

-- Where the third's first step ends: the smallest spot along +X, rounded to one quantum from where it stood
local PARTED: vector = vector.create(2.892578125, FEET, 1.6796875)

-- A walk ahead at a yaw, its presses all off
local function command(number: number, yaw: number): { [string]: any }
	return {
		number = number,
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = yaw,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local Hulls: any = Environment.load(HULLS)
	local Casts: any = Environment.load(CASTS)
	local Scene: any = Environment.load(SCENE)

	local bodies: { any } = {}
	local world: any = Scene.world(Casts({ FLOOR }), bodies)
	local walkers: { any } = {}

	for _, walker: Walker in WALKERS do
		local state: any = Scene.state(walker.feet, true)
		state.velocity = walker.velocity
		table.insert(walkers, state)
		table.insert(bodies, state)
	end

	for _, feet: vector in CROWD do
		table.insert(bodies, Scene.state(feet, true))
	end

	for tick: number = 1, #WALKERS[1].yaws do
		for index: number, walker: Walker in WALKERS do
			local state: any = walkers[index]
			local _: number, stuck: number? = Step.advance(state, command(FIRST + tick - 1, walker.yaws[tick]), world)
			if stuck ~= nil then
				return false, `Walker {index} was reported stuck {stuck} deep on tick {tick}`
			end

			if tick == 1 and index == 1 and (state.position ~= MERGED or not Hulls.block(state, world)) then
				return false,
					`The first walk ended at {state.position}, where {MERGED} inside the third's hull was expected`
			elseif tick == 1 and index == 3 and state.position ~= PARTED then
				return false, `The third walker's first step ended at {state.position}, where {PARTED} was expected`
			end
		end

		for index: number, state: any in walkers do
			if Hulls.block(state, world) then
				return false, `Walker {index} ended tick {tick} at {state.position}, overlapping another hull`
			end
		end
	end

	return true, nil
end
