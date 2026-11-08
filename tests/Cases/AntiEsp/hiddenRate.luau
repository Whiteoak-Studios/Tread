--[[
    A hidden player pair is rechecked at the hidden rate, the example's
    10 Hz: a slice before its recheck is due tests nothing, and one at or
    past it tests the pair again
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

-- Each slice's time and whether it tests the pair, 0.1 s after each test
local SLICES: { { number | boolean } } = {
	{ 0, true },
	{ 0.05, false },
	{ 0.09, false },
	{ 0.11, true },
	{ 0.2, false },
	{ 0.22, true },
	{ 0.5, true },
	{ 0.55, false },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	Harness.AntiEsp.isHidden(viewer, target)

	for _, slice: { number | boolean } in SLICES do
		local now: number = slice[1] :: number
		local tested: boolean = slice[2] :: boolean

		harness:slice(now)

		if (#harness.rays > 0) ~= tested then
			return false,
				`The slice at {now} s cast {#harness.rays} rays, where a test was {tested and "" or "not "}due`
		elseif not Harness.AntiEsp.isHidden(viewer, target) then
			return false, `The pair blocked on every ray was visible after the slice at {now} s`
		end
	end

	return true, nil
end
