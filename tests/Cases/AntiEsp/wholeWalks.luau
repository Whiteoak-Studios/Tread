--[[
    Running whole, a slice's walk reads the clock before each viewer it
    measures and stops at the deadline, testing nothing, and the next
    slice's walk starts at the viewer it stopped at, so a viewer past the
    cut is measured next, not the first viewer again
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EDGE: vector = vector.create(4, 0, 0) -- At the example's 4-stud retest, so its viewer is measured every slice
local PAST: vector = vector.create(5, 0, 0) -- Past it, so its viewer's walk triggers its group

-- Each bot viewer's one sleeper, in the order anti-ESP walks them, the first standing at the retest distance
local PLACES: { vector } = {
	vector.create(-30, 0, 0),
	vector.create(0, 0, 30),
	vector.create(30, 0, 30),
}

-- Each slice's time, its late read, and the sleepers it retests, from the example's 4 studs and 1.5 Hz:
-- the first cut at the third viewer, after the first two; the second tests the second's sleeper, then walks from
-- the third, cut at the first; the third tests the third's sleeper
local STEPS: { { any } } = {
	{ 1, 4, {} },
	{ 1.1, 6, { 2 } },
	{ 1.2, math.huge, { 3 } },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp
	local box: any = harness.shared.step.lyingBox

	AntiEsp.useWhole(true)

	-- Three bot viewers standing at the origin, each with a sleeper of its own
	local viewers: { any } = {}
	local sleepers: { number } = {}
	local heads: { vector } = {}

	for index: number, at: vector in PLACES do
		viewers[index] = harness:viewer(`Walker{index}`, nil)
		sleepers[index] = harness:body("Sleeper", at)
		heads[index] = vector.create(at.x, box.lift, at.z - box.length / 2)
	end

	local function ask()
		for index: number, viewer: any in viewers do
			AntiEsp.isHidden(viewer, sleepers[index])
		end
	end

	-- Each seen from where it stands, then the first stands at the retest distance and the others past it
	ask()
	harness:slice(0)

	viewers[1].position = EDGE
	viewers[2].position = PAST
	viewers[3].position = PAST

	for _, step: { any } in STEPS do
		local now: number = step[1]
		local expected: { number } = step[3]

		ask()
		harness:sliceOn(clock, now, step[2])

		if #harness.rays ~= #expected then
			return false, `The slice at {now} s cast {#harness.rays} rays, not {#expected}`
		end

		for _, sleeper: number in expected do
			if harness:endingAt(heads[sleeper]) ~= 1 then
				return false, `The slice at {now} s didn't retest sleeper {sleeper}`
			end
		end
	end

	if AntiEsp.cuts() ~= 2 then
		return false, `Two walks cut at their deadline counted {AntiEsp.cuts()} cuts`
	end

	return true, nil
end
