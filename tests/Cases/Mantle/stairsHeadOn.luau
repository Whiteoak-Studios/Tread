--[[
    Stairs are never a mantle: facing up flights of 0.5-stud risers with
    treads 0.5, 1 and 1.5 studs deep, from the floor at the foot, on a tread
    partway up and on the landing, the search finds no ledge
--]]

--!strict
local Environment = require("../../Environment")

local STAIRS: string = "tests/Fixtures/Step/Stairs.luau"
local MANTLE: string = "src/Step/Mantle.luau"

return function (): (boolean, string | nil)
	local Stairs: any = Environment.load(STAIRS)
	local Mantle: any = Environment.load(MANTLE)

	for _, depth: number in Stairs.depths do
		local flight: any = Stairs.flight(depth, false)

		for _, place: string in Stairs.places do
			local posture: string? = Mantle.find(Stairs.body(flight[place], Stairs.east), flight.world)
			if posture ~= nil then
				return false, `Up stairs with {depth}-stud treads from the {place}, the search found a mantle {posture}`
			end
		end
	end

	return true, nil
end
