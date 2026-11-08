--[[
    The look-ahead is the viewer's round trip held to the settings' clamp,
    0.15 to 0.45 s in the example: a 1 s round trip widens the side rays and
    moves the last ray's ends by 0.45 s, and a 0.05 s one by 0.15 s
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local SPEED: number = 10 -- The target's studs/s across the line

-- Each bot round trip and the look-ahead it gives
local TRIPS: { { number } } = {
	{ 1, 0.45 },
	{ 0.05, 0.15 },
}

return function (): (boolean, string | nil)
	for _, trip: { number } in TRIPS do
		local rtt: number, lookAhead: number = trip[1], trip[2]
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(function (_: any, server: any)
			server.bots.rtt = rtt
		end)
		harness.wall = Harness.solid

		local slot: number, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", vector.create(0, 0, -50))
		harness.states[slot].velocity = vector.create(0, 0, -SPEED)
		harness.states[target].velocity = vector.create(SPEED, 0, 0)

		Harness.AntiEsp.isHidden(viewer, target)
		harness:slice(0)

		local step: any = harness.shared.step
		local center: vector = vector.create(0, step.standing / 2, -50)
		local width: number = step.radius + SPEED * lookAhead
		local rays: any = harness.rays

		if math.abs(math.abs(rays[3].to.x - center.x) - width) > TOLERANCE then
			return false, `With a {rtt} s round trip the side ray ended {rays[3].to.x} across, not {width}`
		elseif vector.magnitude(rays[5].to - (center + vector.create(SPEED * lookAhead, 0, 0))) > TOLERANCE then
			return false, `With a {rtt} s round trip the moved ray ended at {rays[5].to}`
		elseif math.abs(rays[5].origin.z + SPEED * lookAhead) > TOLERANCE then
			return false, `With a {rtt} s round trip the moved ray started at {rays[5].origin}`
		end
	end

	return true, nil
end
