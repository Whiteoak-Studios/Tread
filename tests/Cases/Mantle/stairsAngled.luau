--[[
    Stairs met at an angle are never a mantle either: turned 30° and 45° off
    the flight's line to either side, from the foot, partway up and on the
    landing, with treads 0.5, 1 and 1.5 studs deep, the search finds none
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

		for _, angle: number in Stairs.angles do
			for _, place: string in Stairs.places do
				local posture: string? = Mantle.find(Stairs.body(flight[place], Stairs.east + angle), flight.world)
				if posture ~= nil then
					local turned: number = math.round(math.deg(angle))
					return false,
						`Up {depth}-stud treads turned {turned}° from the {place}, the search found {posture}`
				end
			end
		end
	end

	return true, nil
end
