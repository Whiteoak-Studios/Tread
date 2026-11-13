--[[
    A jump press on stairs jumps: from the foot, partway up and on the
    landing, head on and turned 30° and 45° either way, the press tick ends
    in the air with the jump counted and no mantle begun
--]]

--!strict
local Environment = require("../../Environment")

local STAIRS: string = "tests/Fixtures/Step/Stairs.luau"

return function (): (boolean, string | nil)
	local Stairs: any = Environment.load(STAIRS)

	local turns: { number } = { 0 }
	table.move(Stairs.angles, 1, #Stairs.angles, 2, turns)

	for _, depth: number in Stairs.depths do
		local flight: any = Stairs.flight(depth, false)

		for _, angle: number in turns do
			for _, place: string in Stairs.places do
				local yaw: number = Stairs.east + angle
				local state: any = Stairs.body(flight[place], yaw)
				Stairs.advance(state, flight.world, Stairs.press(yaw), 1)

				if state.mode ~= "Air" or state.jumps ~= 1 or state.mantleTicks ~= 0 then
					local turned: number = math.round(math.deg(angle))
					local where: string = `on {depth}-stud treads turned {turned}° at the {place}`
					return false, `A press {where} ended {state.mode} with {state.jumps} jumps, not a jump in the air`
				end
			end
		end
	end

	return true, nil
end
