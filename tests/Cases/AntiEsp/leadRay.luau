--[[
    The point marked lead is cast from the viewer's eye moved over the
    look-ahead to its end moved by the target's velocity, and every other
    point from the eye to its own end, wherever in the list lead sits
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LOOK_AHEAD: number = 0.2 -- The harness's bot round trip, inside the example's clamp
local TOLERANCE: number = 1e-6 -- Studs a ray's end or start may sit from where it should
local DRIFT: vector = vector.create(0, 0, -5) -- The viewer's velocity, studs/s
local VELOCITY: vector = vector.create(3, 0, 0) -- The target's, across the line
local TORSO: number = 4 -- The example's leading point
local SHOULDER: number = 2 -- The left shoulder, the side point the second run leads with

return function (): (boolean, string | nil)
	-- With the example's lead, and with it moved from the torso to the left shoulder
	for _, leading: number in { TORSO, SHOULDER } do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(function (_: any, server: any)
			local points: { any } = server.antiEsp.aim.Stand
			points[TORSO].lead = nil
			points[leading].lead = true
		end)
		harness.wall = Harness.solid

		-- A line along -Z, so the viewer's right is +X
		local feet: vector = vector.create(0, 0, -40)
		local slot: number, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", feet)
		harness.states[slot].velocity = DRIFT
		harness.states[target].velocity = VELOCITY

		Harness.AntiEsp.isHidden(viewer, target)
		harness:slice(0)

		local eye: vector = Harness.Eye.clear(harness.states[slot], harness.world)
		local reach: number = vector.magnitude(VELOCITY) * LOOK_AHEAD
		local points: { any } = harness.server.antiEsp.aim.Stand

		for index: number, point: any in points do
			local side: number = point.side + math.sign(point.side) * reach
			local finish: vector = feet + vector.create(side, point.up, 0)
			local origin: vector = eye

			if index == leading then
				finish += VELOCITY * LOOK_AHEAD
				origin += DRIFT * LOOK_AHEAD
			end

			local ray: any = harness.rays[index]
			if vector.magnitude(ray.origin - origin) > TOLERANCE then
				return false, `Leading with point {leading}, ray {index} started at {ray.origin}, not {origin}`
			elseif vector.magnitude(ray.to - finish) > TOLERANCE then
				return false, `Leading with point {leading}, ray {index} ended at {ray.to}, not {finish}`
			end
		end
	end

	return true, nil
end
