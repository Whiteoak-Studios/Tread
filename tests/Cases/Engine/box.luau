--[[
    Engine.box turns a CFrame and a size into the step's oriented box once:
    its center, its right, up and look axes and its size, all on vector
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local ENGINE: string = "src/Step/Engine.luau"
local TOLERANCE: number = 1e-6 -- Past float32's rounding of a turned axis

local function apart(a: vector, b: vector): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y), math.abs(a.z - b.z))
end

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)

	-- A quarter turn about Y, so each axis lands on a world axis
	local cframe: any = roblox.CFrame.new(10, 1102, -4) * roblox.CFrame.Angles(0, math.pi / 2, 0)
	local size: any = roblox.Vector3.new(4, 7, 0.5)
	local made: { [string]: vector } = Engine.box(cframe, size)

	local wanted: { [string]: vector } = {
		center = vector.create(10, 1102, -4),
		right = vector.create(0, 0, -1),
		up = vector.create(0, 1, 0),
		look = vector.create(-1, 0, 0),
		size = vector.create(4, 7, 0.5),
	}

	for field: string, want: vector in wanted do
		local got: vector = made[field]
		if typeof(got) ~= "vector" then
			return false, `Engine.box's {field} is a {typeof(got)}, not a vector`
		elseif apart(got, want) > TOLERANCE then
			return false, `Engine.box's {field} is {got}, where {want} was expected`
		end
	end

	return true, nil
end
