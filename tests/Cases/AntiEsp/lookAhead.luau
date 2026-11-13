--[[
    The look-ahead is the viewer's round trip held to the settings' clamp,
    0.15 to 0.45 s in the example: a 1 s round trip widens the side points
    and moves the leading ray's ends by 0.45 s, and a 0.05 s one by 0.15 s
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local SPEED: number = 10 -- The target's studs/s across the line
local SHOULDER: number = 3 -- The example's right shoulder among the standing points
local TORSO: number = 4 -- And its torso, the point that leads

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

		local feet: vector = vector.create(0, 0, -50)
		local slot: number, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", feet)
		harness.states[slot].velocity = vector.create(0, 0, -SPEED)
		harness.states[target].velocity = vector.create(SPEED, 0, 0)

		Harness.AntiEsp.isHidden(viewer, target)
		harness:slice(0)

		local points: { any } = harness.server.antiEsp.aim.Stand
		local width: number = points[SHOULDER].side + SPEED * lookAhead
		local torso: vector = feet + vector.create(SPEED * lookAhead, points[TORSO].up, 0)
		local rays: any = harness.rays

		if math.abs(rays[SHOULDER].to.x - feet.x - width) > TOLERANCE then
			return false, `With a {rtt} s round trip the shoulder's ray ended {rays[SHOULDER].to.x} across, not {width}`
		elseif vector.magnitude(rays[TORSO].to - torso) > TOLERANCE then
			return false, `With a {rtt} s round trip the leading ray ended at {rays[TORSO].to}, not {torso}`
		elseif math.abs(rays[TORSO].origin.z + SPEED * lookAhead) > TOLERANCE then
			return false, `With a {rtt} s round trip the leading ray started at {rays[TORSO].origin}`
		end
	end

	return true, nil
end
