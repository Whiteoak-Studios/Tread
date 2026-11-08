--[[
    Stairs that lead up to a 3-stud ledge: from the top tread facing the
    ledge, head on and turned 30° and 45° either way, with treads 0.5, 1 and
    1.5 studs deep, the search finds the mantle onto it standing
--]]

--!strict
local Environment = require("../../Environment")

local STAIRS: string = "tests/Fixtures/Step/Stairs.luau"
local MANTLE: string = "src/Step/Mantle.luau"

return function (): (boolean, string | nil)
	local Stairs: any = Environment.load(STAIRS)
	local Mantle: any = Environment.load(MANTLE)

	local turns: { number } = { 0 }
	table.move(Stairs.angles, 1, #Stairs.angles, 2, turns)

	for _, depth: number in Stairs.depths do
		local flight: any = Stairs.flight(depth, true)

		for _, angle: number in turns do
			local posture: string? = Mantle.find(Stairs.body(flight.top, Stairs.east + angle), flight.world)
			if posture ~= "Stand" then
				local turned: number = math.round(math.deg(angle))
				return false,
					`At the ledge over {depth}-stud treads turned {turned}°, the search gave {posture}, not Stand`
			end
		end
	end

	return true, nil
end
