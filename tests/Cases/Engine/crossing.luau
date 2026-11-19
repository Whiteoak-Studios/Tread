--[[
    Engine.toVector and toVector3 copy a value across the boundary component
    for component, both ways and both float32, so a crossing loses nothing
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local ENGINE: string = "src/Step/Engine.luau"

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)

	-- A quantized position at the play bound's edge, a fraction float32 rounds and a negative zero
	local values: { { number } } = {
		{ 8191.998046875, -1100.01953125, 0.25 },
		{ 0.1, 1 / 3, -2.5 },
		{ -0, 512, -511.984375 },
	}

	for _, components: { number } in values do
		local public: any = roblox.Vector3.new(components[1], components[2], components[3])
		local inner: vector = Engine.toVector(public)

		if typeof(inner) ~= "vector" then
			return false, `Engine.toVector gave a {typeof(inner)}, not a vector`
		elseif inner.x ~= public.X or inner.y ~= public.Y or inner.z ~= public.Z then
			return false, `Engine.toVector of {public} gave {inner}`
		end

		local back: any = Engine.toVector3(inner)
		if typeof(back) ~= "Vector3" then
			return false, `Engine.toVector3 gave a {typeof(back)}, not a Vector3`
		elseif back ~= public then
			return false, `Engine.toVector3 of {inner} gave {back}, where {public} went in`
		end
	end

	return true, nil
end
