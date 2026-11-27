--[[
    Each posture's ends for a still target lie side studs to the viewer's
    right of its feet raised by up, whichever way it faces: +X for a line
    along -Z and +Z for a line along +X, for a positive side
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local DISTANCE: number = 40 -- Studs from the viewer to the target
local GAP: number = 0.001 -- Seconds between slices, inside every recheck interval
local FACINGS: { number } = { 0, math.pi / 2, math.pi, -2.3 } -- Radians
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }

-- Each line from the viewer at the origin: where the target's feet stand, and the viewer's right along it
local LINES: { { vector } } = {
	{ vector.create(0, 0, -DISTANCE), vector.create(1, 0, 0) },
	{ vector.create(DISTANCE, 0, 0), vector.create(0, 0, 1) },
}

return function (): (boolean, string | nil)
	for _, line: { vector } in LINES do
		local feet: vector, right: vector = line[1], line[2]
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new()
		harness.wall = Harness.solid

		local _, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", feet)
		local state: any = harness.states[target]
		local now: number = 0

		for _, posture: string in POSTURES do
			local points: { any } = harness.server.antiEsp.aim[posture]

			for _, facing: number in FACINGS do
				state.posture = posture
				state.facing = facing

				-- Due at once, so each slice tests the pair at its new posture and facing
				Harness.AntiEsp.isHidden(viewer, target)
				Harness.AntiEsp.moved(target)
				harness:slice(now)
				now += GAP

				local seen: string = `A {posture} target at {feet} facing {facing}`
				if #harness.rays ~= #points then
					return false, `{seen} took {#harness.rays} rays, not {#points}`
				end

				for index: number, point: any in points do
					local finish: vector = feet + vector.create(0, point.up, 0) + right * point.side
					local ended: vector = harness.rays[index].to

					if vector.magnitude(ended - finish) > TOLERANCE then
						return false, `{seen} had its point {index} at {ended}, not {finish}`
					end
				end
			end
		end
	end

	return true, nil
end
