--[[
    World.new seeds a world's gravity from its settings, and World.setGravity
    keeps the latest change by its tick and the value before it, which the
    step gives the ticks before the change, and refuses what it cannot take
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local WORLD: string = "src/Step/World.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local REFUSAL: string = "World.setGravity" -- What every refusal names

local RATE: number = 20
local HIGH: number = 500 -- Studs up where each one-tick fall starts, clear of everything in an empty scene
local WRAP: number = 2 ^ 16 -- The ticks a u16 holds, which world.tick wraps in
local FIRST_AT: number = 10 -- The first change's tick, unwrapped
local FIRST: number = 30 -- Studs/s², the first change's gravity
local SECOND_AT: number = 20
local SECOND: number = 50
local REPLACED: number = 40 -- Given again on the second change's tick
local EARLIER_AT: number = 15 -- A tick between the two changes, which the latest change makes too early
local EARLIER: number = 90
local LATER_AT: number = 30 -- A tick past the latest change, which a refused gravity is given with
local FRACTIONAL_AT: number = 30.5 -- A tick past the latest change that is no whole tick

local function rules(_: any, _: any): number
	return math.huge
end

-- A command with no input, numbered as the tick it runs on
local function newCommand(number: number): any
	return {
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
end

-- Why a world's record isn't the gravity, the value before it and the change's tick given, or nil when it is
local function recordOf(world: any, gravity: number, before: number, at: number?): string?
	if world.gravity ~= gravity or world.gravityBefore ~= before or world.gravityAt ~= at then
		local kept: string = `{world.gravity}, and {world.gravityBefore} before tick {world.gravityAt}`
		local wanted: string = `{gravity}, and {before} before tick {at}`

		return `the world kept a gravity of {kept}, where {wanted} was expected`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Step: any = Environment.load(STEP)
	local World: any = Environment.load(WORLD)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(CASTS)

	local base: number = Scene.settings.gravity
	local world: any = World.new(Scene.settings, RATE, Casts({}), nil, rules, true)

	-- Why a body at rest in the air, stepped one tick as the unwrapped tick, doesn't fall under gravity, or nil
	local function under(tick: number, gravity: number): string?
		local body: any = Scene.state(vector.create(0, HIGH, 0), false)
		world.tick = tick % WRAP
		world.clock = tick
		Step.advance(body, newCommand(tick % WRAP), world)

		-- The air's update as the step makes it: a tick of gravity off its speed, held in a vector, on the quantum
		local speed: number = Math.quantizeVelocity(vector.create(0, -gravity * world.delta, 0).y)
		if body.velocity.y ~= speed then
			return `tick {tick} fell at {body.velocity.y}, where {speed} under a gravity of {gravity} was expected`
		end

		return nil
	end

	-- 1) World.new seeds the gravity and the value before any change from the settings, with no change's tick
	local failure: string? = recordOf(world, base, base, nil) or under(FIRST_AT, base)
	if failure then
		return false, `World.new: {failure}`
	end

	-- 2) A change: the ticks before it fall under the settings' gravity, and it and those after under its own
	World.setGravity(world, FIRST, FIRST_AT)
	failure = recordOf(world, FIRST, base, FIRST_AT)
		or under(FIRST_AT - 1, base)
		or under(FIRST_AT, FIRST)
		or under(FIRST_AT + 1, FIRST)
	if failure then
		return false, `After the first change {failure}`
	end

	-- 3) A second change: the ticks between the two fall under the first, and from it on under the second
	World.setGravity(world, SECOND, SECOND_AT)
	failure = recordOf(world, SECOND, FIRST, SECOND_AT) or under(SECOND_AT - 1, FIRST) or under(SECOND_AT, SECOND)
	if failure then
		return false, `After the second change {failure}`
	end

	-- 4) A change on the latest change's tick replaces it and keeps the value before it
	World.setGravity(world, REPLACED, SECOND_AT)
	failure = recordOf(world, REPLACED, FIRST, SECOND_AT) or under(SECOND_AT - 1, FIRST) or under(SECOND_AT, REPLACED)
	if failure then
		return false, `After a change on the same tick {failure}`
	end

	-- 5) A change on a tick before the latest changes nothing
	World.setGravity(world, EARLIER, EARLIER_AT)
	failure = recordOf(world, REPLACED, FIRST, SECOND_AT) or under(EARLIER_AT, FIRST)
	if failure then
		return false, `After a change on an earlier tick {failure}`
	end

	-- 6) Every refusal names World.setGravity and leaves the record as it was
	for _, gravity: any in { 0 / 0, math.huge, -math.huge, 0, -1, "1" } do
		local ran: boolean, message: any = pcall(World.setGravity, world, gravity, LATER_AT)
		if ran then
			return false, `World.setGravity took a gravity of {gravity}`
		elseif not string.find(`{message}`, REFUSAL, 1, true) then
			return false, `World.setGravity's refusal of a gravity of {gravity} was something else: {message}`
		end

		failure = recordOf(world, REPLACED, FIRST, SECOND_AT)
		if failure then
			return false, `After refusing a gravity of {gravity} {failure}`
		end
	end

	for _, tick: any in { FRACTIONAL_AT, 0 / 0 } do
		local ran: boolean, message: any = pcall(World.setGravity, world, FIRST, tick)
		if ran then
			return false, `World.setGravity took the tick {tick}`
		elseif not string.find(`{message}`, REFUSAL, 1, true) then
			return false, `World.setGravity's refusal of the tick {tick} was something else: {message}`
		end

		failure = recordOf(world, REPLACED, FIRST, SECOND_AT)
		if failure then
			return false, `After refusing the tick {tick} {failure}`
		end
	end

	return true, nil
end
