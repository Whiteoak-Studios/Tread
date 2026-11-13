--[[
    World.setBodies hands the world this tick's live bodies as the list given,
    and refuses anything that is no list
--]]

--!strict
local Environment = require("../../Environment")

local WORLD: string = "src/Step/World.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local REFUSAL: string = "bodies must be a list of states"

local function rules(_: any, _: any): number
	return math.huge
end

return function (): (boolean, string | nil)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local world: any = World.new(Scene.settings, 20, Environment.load(CASTS)({}), nil, rules, true)

	local bodies: { any } = { Scene.state(vector.zero, true), Scene.state(vector.one, false) }
	World.setBodies(world, bodies)
	if world.bodies ~= bodies then
		return false, "the world did not take the list of bodies given"
	end

	local ran: boolean, message: any = pcall(World.setBodies, world, 3)
	if ran then
		return false, "World.setBodies took a number"
	elseif not string.find(`{message}`, REFUSAL, 1, true) then
		return false, `World.setBodies's refusal of a number was something else: {message}`
	end

	return true, nil
end
