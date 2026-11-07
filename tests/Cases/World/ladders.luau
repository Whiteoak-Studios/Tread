--[[
    World.addLadder turns each ladder into the step's numbers once, gives it
    an id from its own box, and hands back the closure that takes it out,
    harmless twice; a ladder with no size on some axis is refused
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local WORLD: string = "src/Step/World.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local REFUSAL: string = "A ladder needs a size above 0"

local function rules(_: any, _: any): number
	return math.huge
end

return function (): (boolean, string | nil)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local world: any = World.new(Scene.settings, 20, Environment.load(CASTS)({}), nil, rules, true)

	local at: any = roblox.CFrame.new(1, 2, 3)
	local size: any = roblox.Vector3.new(2, 10, 1)
	local removeFirst: () -> () = World.addLadder(world, at, size)
	local removeSecond: () -> () = World.addLadder(world, at + roblox.Vector3.new(5, 0, 0), size)

	local first: any = world.ladders[1]
	local second: any = world.ladders[2]
	if not first or first.id == 0 or not second or second.id == 0 or first.id == second.id then
		return false, "two ladders did not take two ids above 0"
	elseif first.box.center ~= vector.create(1, 2, 3) or first.box.size ~= vector.create(2, 10, 1) then
		return false, `the first ladder's box was at {first.box.center} sized {first.box.size}`
	elseif first.box.up ~= vector.create(0, 1, 0) then
		return false, `an unturned ladder's up was {first.box.up}`
	end

	removeFirst()
	removeFirst()
	if #world.ladders ~= 1 or world.ladders[1] ~= second then
		return false, "taking the first ladder out, twice, did not leave the second alone"
	end

	World.addLadder(world, at, size)
	if world.ladders[2].id ~= first.id then
		return false, `the first's box added again took the id {world.ladders[2].id}, where {first.id} was expected`
	end

	removeSecond()
	for _, ladder: any in world.ladders do
		if ladder == second then
			return false, "the second ladder's closure did not take it out"
		end
	end

	for _, bad: any in { roblox.Vector3.new(0, 10, 1), roblox.Vector3.new(2, -10, 1) } do
		local ran: boolean, message: any = pcall(World.addLadder, world, at, bad)
		if ran then
			return false, `World.addLadder took the size {bad}`
		elseif not string.find(`{message}`, REFUSAL, 1, true) then
			return false, `World.addLadder's refusal of the size {bad} was something else: {message}`
		end
	end

	return true, nil
end
