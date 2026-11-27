--[[
    World.new builds the step's world, its time step one tick of the
    simulation rate and the lean's shift crossed once, and refuses a rate
    that is no finite number above 0 and rules that are no function
--]]

--!strict
local Environment = require("../../Environment")

local WORLD: string = "src/Step/World.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local RATE: number = 20
local RATE_REFUSAL: string = "simulation rate must be a finite number above 0"
local RULES_REFUSAL: string = "rules must be a function"

local function rules(_: any, _: any): number
	return math.huge
end

local function water(_: number, _: number): number?
	return nil
end

return function (): (boolean, string | nil)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local collision: any = Environment.load(CASTS)({})

	local world: any = World.new(Scene.settings, RATE, collision, water, rules, true)
	local shift: Vector3 = Scene.settings.leanShift

	if world.delta ~= 1 / RATE then
		return false, `the world's delta was {world.delta}, where {1 / RATE} was expected`
	elseif world.leanShift ~= vector.create(shift.X, shift.Y, shift.Z) then
		return false, `the world's leanShift was {world.leanShift}, where {shift} crossed was expected`
	elseif world.settings ~= Scene.settings or world.collision ~= collision then
		return false, "the world lost its settings or its collision"
	elseif world.water ~= water or world.rules ~= rules or world.isServer ~= true then
		return false, "the world lost its water, its rules or its realm"
	elseif world.tick ~= 0 or #world.ladders ~= 0 or #world.bodies ~= 0 then
		return false, "a new world started with a tick, a ladder or a body"
	end

	for _, rate: any in { 0, -RATE, 0 / 0, math.huge, `{RATE}` } do
		local ran: boolean, message: any = pcall(World.new, Scene.settings, rate, collision, nil, rules, true)
		if ran then
			return false, `World.new took the rate {rate}`
		elseif not string.find(`{message}`, RATE_REFUSAL, 1, true) then
			return false, `World.new's refusal of the rate {rate} was something else: {message}`
		end
	end

	local ran: boolean, message: any = pcall(World.new, Scene.settings, RATE, collision, nil, RATE, false)
	if ran then
		return false, "World.new took rules that are a number"
	elseif not string.find(`{message}`, RULES_REFUSAL, 1, true) then
		return false, `World.new's refusal of rules that are a number was something else: {message}`
	end

	return true, nil
end
