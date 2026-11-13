--[[
    Yaw between two records takes the shortest arc through
    Sequence.difference, so 350° to 10° passes 0°, never 180°
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 9
local GENERATION: number = 1
local TOLERANCE: number = math.rad(0.01)

-- How far apart two angles are around the turn, in radians
local function apart(a: number, b: number): number
	local difference: number = (a - b) % (2 * math.pi)

	return math.min(difference, 2 * math.pi - difference)
end

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	viewer.announce(SLOT, GENERATION, "A")
	viewer.send({
		tick = 100,
		reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } },
		records = { { slot = SLOT, generation = GENERATION, position = vector.zero, yaw = math.rad(350) } },
	})
	viewer.send({
		tick = 101,
		records = { { slot = SLOT, generation = GENERATION, position = vector.zero, yaw = math.rad(10) } },
	})
	viewer.send({ tick = 102 })
	viewer.send({ tick = 103 })

	-- 3 ticks behind 103, then half a tick on, half way between the records
	Interpolate.frame(0)
	Interpolate.frame(0.025)

	local drawn: boolean, state: any = viewer.pose(SLOT)
	if not drawn then
		return false, "The slot drew nothing between its two records"
	elseif state.facing < 0 or state.facing >= 2 * math.pi then
		return false, `The pose's facing {state.facing} is outside one turn from 0`
	elseif apart(state.facing, 0) > TOLERANCE then
		return false, `Half way from 350° to 10° the slot faced {math.deg(state.facing)}°, not 0°`
	end

	-- A quarter tick more, three quarters of the way, at 5°
	Interpolate.frame(0.0125)

	drawn, state = viewer.pose(SLOT)
	if not drawn or apart(state.facing, math.rad(5)) > TOLERANCE then
		return false, `Three quarters of the way from 350° to 10° the slot faced {math.deg(state.facing)}°, not 5°`
	end

	return true, nil
end
