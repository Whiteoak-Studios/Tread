--[[
    A new enemy pair starts hidden, and its test casts all five rays from
    the viewer's cleared eye, leaning, to the target's head, center and
    either side, and between the two moved, staying hidden with all blocked
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
	local target: number = harness:body("Player", vector.create(0, 0, -50))

	local own: any = harness.states[slot]
	own.lean = LEAN
	own.velocity = vector.create(0, 0, -5)
	harness.states[target].velocity = vector.create(10, 0, 0)

	if not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "A new enemy pair was not hidden before its first test"
	end

	harness:slice(0)

	local step: any = harness.shared.step
	local eye: vector = Harness.Eye.clear(own, harness.world)
	if #harness.rays ~= 5 then
		return false, `The test cast {#harness.rays} rays, not 5`
	end

	for index: number = 1, 4 do
		if harness.rays[index].origin ~= eye then
			return false, `Ray {index} started at {harness.rays[index].origin}, not the cleared eye {eye}`
		end
	end

	-- The side rays push across the line by the hull radius and the target's 10 studs/s over the look-ahead
	local center: vector = vector.create(0, step.standing / 2, -50)
	local toward: vector = center - eye
	local level: number = math.sqrt(toward.x * toward.x + toward.z * toward.z)
	local across: vector = vector.create(toward.z / level, 0, -toward.x / level) * (step.radius + 10 * LOOK_AHEAD)
	local expected: { vector } = {
		vector.create(0, step.eyeStanding, -50),
		center,
		center + across,
		center - across,
		center + vector.create(10, 0, 0) * LOOK_AHEAD,
	}

	for index: number, point: vector in expected do
		if vector.magnitude(harness.rays[index].to - point) > TOLERANCE then
			return false, `Ray {index} ended at {harness.rays[index].to}, not {point}`
		end
	end

	local moved: vector = eye + vector.create(0, 0, -5) * LOOK_AHEAD
	if vector.magnitude(harness.rays[5].origin - moved) > TOLERANCE then
		return false, `The moved ray started at {harness.rays[5].origin}, not the eye moved to {moved}`
	elseif not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "A pair whose every ray was blocked was not hidden"
	end

	return true, nil
end
