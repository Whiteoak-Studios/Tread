--[[
    State.new sets every field of the step state, at rest at the origin,
    airborne, standing and walking, with empty game blocks of its own
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local STATE: string = "src/Step/State.luau"
local AIR: any = roblox.Enum.Material.Air

return function (): (boolean, string | nil)
	local State: any = Environment.load(STATE)

	local wanted: { [string]: any } = {
		command = 0,
		tick = 0,
		depth = 0,
		position = vector.zero,
		velocity = vector.zero,
		facing = 0,
		mode = "Air",
		posture = "Stand",
		sprint = false,
		aim = false,
		waterLevel = "Dry",
		jumps = 0,
		lands = 0,
		heavy = false,
		epoch = 0,
		platform = 0,
		moveMode = "Walk",
		grounded = false,
		lean = 0,
		eyeHeight = 0,
		apex = 0,
		groundHeight = 0,
		groundTicks = 0,
		airTicks = 0,
		mantleTicks = 0,
		mantleRise = 0,
		ladder = 0,
		groundNormal = vector.zero,
		groundMaterial = AIR,
		npc = false,
	}

	local first: { [string]: any } = State.new()
	local second: { [string]: any } = State.new()

	for field: string, value: any in wanted do
		if first[field] ~= value then
			return false, `State.new set {field} to {first[field]}, where {value} was expected`
		end
	end

	-- Every field it sets is one of the step's, its three game blocks aside
	for field: string in first do
		local block: boolean = field == "fields" or field == "block" or field == "held"
		if wanted[field] == nil and not block then
			return false, `State.new set {field}, which no field of the step state is`
		end
	end

	for _, block: string in { "fields", "block", "held" } do
		if type(first[block]) ~= "table" or next(first[block]) ~= nil then
			return false, `State.new's {block} is not an empty table`
		elseif first[block] == second[block] then
			return false, `Two states from State.new share one {block} table`
		end
	end

	return true, nil
end
