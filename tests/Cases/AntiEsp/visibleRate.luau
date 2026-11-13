--[[
    A visible player pair is rechecked at the visible rate, the example's
    2 Hz: a slice before its recheck is due tests nothing, and one at or
    past it tests the pair again
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

-- Each slice's time and whether it tests the pair, 0.5 s after each test
local SLICES: { { number | boolean } } = {
	{ 0, true },
	{ 0.1, false },
	{ 0.49, false },
	{ 0.51, true },
	{ 1, false },
	{ 1.02, true },
	{ 1.3, false },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

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
		elseif Harness.AntiEsp.isHidden(viewer, target) then
			return false, `The pair with every ray open was hidden after the slice at {now} s`
		end
	end

	return true, nil
end
