--[[
    A new enemy pair starts hidden, and its test casts all six rays from
    the viewer's cleared eye, leaning, to the standing target's six aim
    points, the torso's between the two moved, staying hidden with all
    blocked
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LOOK_AHEAD: number = 0.2 -- The harness's bot round trip, inside the example's clamp
local LEAN: number = 12 -- Degrees, so the eye sits off the head's center
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local feet: vector = vector.create(0, 0, -50)
	local target: number = harness:body("Player", feet)

	local own: any = harness.states[slot]
	own.lean = LEAN
	own.velocity = vector.create(0, 0, -5)
	harness.states[target].velocity = vector.create(10, 0, 0)

	if not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "A new enemy pair was not hidden before its first test"
	end

	harness:slice(0)

	local points: { any } = harness.server.antiEsp.aim.Stand
	local eye: vector = Harness.Eye.clear(own, harness.world)
	if #harness.rays ~= #points then
		return false, `The test cast {#harness.rays} rays, not {#points}`
	end

	-- The viewer's right across the level line to the target, and the target's 10 studs/s over the look-ahead
	local toward: vector = feet - eye
	local level: number = math.sqrt(toward.x * toward.x + toward.z * toward.z)
	local right: vector = vector.create(-toward.z / level, 0, toward.x / level)
	local reach: number = 10 * LOOK_AHEAD
	local moved: vector = eye + vector.create(0, 0, -5) * LOOK_AHEAD

	for index: number, point: any in points do
		local side: number = point.side + math.sign(point.side) * reach
		local finish: vector = feet + vector.create(0, point.up, 0) + right * side
		local origin: vector = eye

		if point.lead then
			finish += vector.create(10, 0, 0) * LOOK_AHEAD
			origin = moved
		end

		local ray: any = harness.rays[index]
		if vector.magnitude(ray.to - finish) > TOLERANCE then
			return false, `Ray {index} ended at {ray.to}, not {finish}`
		elseif vector.magnitude(ray.origin - origin) > TOLERANCE then
			return false, `Ray {index} started at {ray.origin}, not {origin}`
		end
	end

	if not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "A pair whose every ray was blocked was not hidden"
	end

	return true, nil
end
