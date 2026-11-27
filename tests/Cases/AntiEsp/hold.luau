--[[
    A visible player pair stays visible through the hold when its tests
    find every ray blocked, hides at the first such test past it, and shows
    again at once when a ray opens, with no hold on the way back
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

-- Each slice's time, whether its walls block, and whether the pair is hidden after it, from the example's 1 s hold
-- and 2 Hz and 10 Hz rechecks
local STEPS: { { number | boolean } } = {
	{ 0, false, false },
	{ 0.5, true, false },
	{ 1, true, false },
	{ 1.5, true, true },
	{ 1.6, false, false },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	Harness.AntiEsp.isHidden(viewer, target)

	for index: number, step: { number | boolean } in STEPS do
		local now: number = step[1] :: number
		local walls: boolean = step[2] :: boolean
		local hidden: boolean = step[3] :: boolean

		if walls then
			harness.wall = Harness.solid
		else
			harness.wall = Harness.open
		end

		harness:slice(now)

		if #harness.rays == 0 then
			return false, `Slice {index} at {now} s tested nothing`
		elseif Harness.AntiEsp.isHidden(viewer, target) ~= hidden then
			return false, `After the slice at {now} s the pair was not {hidden and "hidden" or "visible"}`
		end
	end

	return true, nil
end
