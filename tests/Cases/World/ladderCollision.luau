--[[
    A ladder whose id another registered ladder already holds is refused
    with an error naming both, whether it is the same box again or another
    box whose hash shares the low 16 bits, and the world keeps the first
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local WORLD: string = "src/Step/World.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local REFUSAL: string = "already holds"

-- Two boxes found by search whose hashes share their low 16 bits, both taking the id 1391
local HOLDER: Vector3 = roblox.Vector3.new(1004, 1100, 66)
local CLASHING: Vector3 = roblox.Vector3.new(1006, 1100, 2)

type Pair = { label: string, first: any, second: any }

local function rules(_: any, _: any): number
	return math.huge
end

return function (): (boolean, string | nil)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(CASTS)
	local size: any = roblox.Vector3.new(0.5, 10, 2)

	local clashes: { Pair } = {
		{
			label = "the same box twice",
			first = roblox.CFrame.new(3, 1102, 5),
			second = roblox.CFrame.new(3, 1102, 5),
		},
		{
			label = "two boxes sharing the low bits",
			first = roblox.CFrame.new(HOLDER.X, HOLDER.Y, HOLDER.Z),
			second = roblox.CFrame.new(CLASHING.X, CLASHING.Y, CLASHING.Z),
		},
	}

	for _, pair: Pair in clashes do
		local world: any = World.new(Scene.settings, 20, Casts({}), nil, rules, true)
		World.addLadder(world, pair.first, size)
		local held: any = world.ladders[1]

		local ran: boolean, message: any = pcall(World.addLadder, world, pair.second, size)
		local secondAt: vector = vector.create(pair.second.Position.X, pair.second.Position.Y, pair.second.Position.Z)
		local text: string = `{message}`

		if ran then
			return false, `World.addLadder took {pair.label}`
		elseif not string.find(text, REFUSAL, 1, true) then
			return false, `World.addLadder's refusal of {pair.label} was something else: {message}`
		elseif not string.find(text, `{held.box.center}`, 1, true) or not string.find(text, `{secondAt}`, 1, true) then
			return false, `World.addLadder's refusal of {pair.label} did not name both ladders: {message}`
		elseif #world.ladders ~= 1 or world.ladders[1] ~= held then
			return false, `refusing {pair.label} left the world {#world.ladders} ladders, not the first alone`
		end
	end

	return true, nil
end
