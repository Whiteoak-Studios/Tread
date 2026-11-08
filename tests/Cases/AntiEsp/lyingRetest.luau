--[[
    A sleeper pair's three rays go from the eye to the lying box's head,
    chest and feet, and it is retested only once the viewer has walked more
    than sleepers.retest since its last test, at most sleepers.rate a second
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local FACING: number = math.pi / 2 -- Lying along -X

-- Each slice's time, where the viewer stands by then, and whether the slice retests, from the example's 4 studs
-- and 1.5 Hz
local STEPS: { { any } } = {
	{ 1, vector.zero, false }, -- Still
	{ 2, vector.create(3, 0, 0), false }, -- 3 studs from the last test
	{ 3, vector.create(5, 0, 0), true }, -- 5 studs
	{ 3.2, vector.create(10, 0, 0), false }, -- 5 more, but 0.2 s after the last test
	{ 3.7, vector.create(10, 0, 0), true }, -- Past 1 / 1.5 s
	{ 5, vector.create(10, 0, 4), false }, -- Exactly 4 studs
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local sleeper: number = harness:body("Sleeper", vector.create(0, 0, -50), FACING)

	Harness.AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0)

	local box: any = harness.shared.step.lyingBox
	local center: vector = vector.create(0, box.lift, -50)
	local along: vector = vector.create(-box.length / 2, 0, 0)

	if #harness.rays ~= 3 then
		return false, `The sleeper's test cast {#harness.rays} rays, not 3`
	end

	for name: string, point: vector in { head = center + along, chest = center, feet = center - along } do
		if harness:endingAt(point) ~= 1 then
			return false, `No ray went to the lying box's {name} at {point}`
		end
	end

	for _, step: { any } in STEPS do
		local now: number = step[1]
		harness:move(slot, step[2], viewer)
		Harness.AntiEsp.isHidden(viewer, sleeper)
		harness:slice(now)

		if (#harness.rays > 0) ~= step[3] then
			return false, `At {now} s, standing at {step[2]}, the sleeper pair cast {#harness.rays} rays`
		elseif not Harness.AntiEsp.isHidden(viewer, sleeper) then
			return false, `The sleeper pair blocked on every ray was visible at {now} s`
		end
	end

	return true, nil
end
