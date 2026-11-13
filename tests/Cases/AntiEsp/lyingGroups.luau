--[[
    Sleeper pairs tested at different times keep their own walks and rates:
    a walk retests only those the rate allows, the others once it does,
    and a viewer back inside the retest distance before the rate passes is
    not retested
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

-- Each slice's time, where the viewer stands by then, and the sleepers whose rays it casts, from the example's
-- 4 studs and 1.5 Hz
local STEPS: { { any } } = {
	{ 1.2, vector.create(5, 0, 0), { 1 } }, -- The second, tested at 1 s, waits for its rate
	{ 1.5, vector.create(5, 0, 0), {} },
	{ 1.7, vector.create(5, 0, 0), { 2 } }, -- Its rate passes with the viewer still away
	{ 2, vector.create(5, 0, 0), {} },
	{ 3, vector.create(10, 0, 0), { 1, 2 } },
	{ 3.3, vector.create(16, 0, 0), {} }, -- Too soon after 3 s
	{ 3.5, vector.create(10, 0, 0), {} }, -- Back where both were tested
	{ 3.7, vector.create(10, 0, 0), {} }, -- Their rate passes with the viewer inside
	{ 4, vector.create(10, 0, 0), {} },
	{ 4.1, vector.create(15, 0, 0), { 1, 2 } },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local box: any = harness.shared.step.lyingBox
	local sleepers: { number } = {}
	local heads: { vector } = {}

	-- Facing 0, each lies along -Z with its head half the box's length that way
	for index: number, z: number in { -50, 50 } do
		sleepers[index] = harness:body("Sleeper", vector.create(0, 0, z))
		heads[index] = vector.create(0, box.lift, z - box.length / 2)
	end

	local function ask(count: number)
		for index: number = 1, count do
			AntiEsp.isHidden(viewer, sleepers[index])
		end
	end

	-- The first tested at 0 s and the second at 1 s, the viewer standing still
	ask(1)
	harness:slice(0)
	ask(2)
	harness:slice(1)

	if #harness.rays ~= 3 or harness:endingAt(heads[2]) ~= 1 then
		return false, `The second sleeper's first test at 1 s cast {#harness.rays} rays`
	end

	for _, step: { any } in STEPS do
		local now: number = step[1]
		local expected: { number } = step[3]

		harness:move(slot, step[2], viewer)
		ask(2)
		harness:slice(now)

		if #harness.rays ~= 3 * #expected then
			return false, `At {now} s, standing at {step[2]}, the slice cast {#harness.rays} rays`
		end

		for _, index: number in expected do
			if harness:endingAt(heads[index]) ~= 1 then
				return false, `At {now} s sleeper {index} was not retested`
			end
		end
	end

	return true, nil
end
