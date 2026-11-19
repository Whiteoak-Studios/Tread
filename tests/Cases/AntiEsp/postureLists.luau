--[[
    A target's rays aim at its posture's points, a swimming standing body at
    Crouch's as its hull is a crouched one, a downed body at Downed's in or
    out of water, and a standing body out of water at Stand's
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local GAP: number = 0.001 -- Seconds between slices, inside every recheck interval

-- Each body's posture and mode, and the list its rays aim at
local BODIES: { { string } } = {
	{ "Stand", "Ground", "Stand" },
	{ "Stand", "Swim", "Crouch" },
	{ "Crouch", "Ground", "Crouch" },
	{ "Crouch", "Swim", "Crouch" },
	{ "Downed", "Ground", "Downed" },
	{ "Downed", "Swim", "Downed" },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	-- A line along -Z, so the viewer's right is +X
	local feet: vector = vector.create(0, 0, -40)
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", feet)
	local state: any = harness.states[target]

	for row: number, body: { string } in BODIES do
		state.posture = body[1]
		state.mode = body[2]

		-- Due at once, so each slice tests the pair as the body is now
		Harness.AntiEsp.isHidden(viewer, target)
		Harness.AntiEsp.moved(target)
		harness:slice(row * GAP)

		local points: { any } = harness.server.antiEsp.aim[body[3]]
		local seen: string = `A {body[1]} body in {body[2]}`
		if #harness.rays ~= #points then
			return false, `{seen} took {#harness.rays} rays, not {body[3]}'s {#points}`
		end

		for index: number, point: any in points do
			local finish: vector = feet + vector.create(point.side, point.up, 0)
			if vector.magnitude(harness.rays[index].to - finish) > TOLERANCE then
				return false, `{seen} had its ray {index} end at {harness.rays[index].to}, not {body[3]}'s {finish}`
			end
		end
	end

	return true, nil
end
