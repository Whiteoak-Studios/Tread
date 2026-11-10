--[[
    A pair moved before its recheck is tested at once and then on its new
    schedule alone, the old one's time passing with no test, and a recheck
    due exactly at a slice's time is tested in that slice
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local MOVED: number = 0.05 -- Halfway to the first recheck

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -300)) -- Past the near radius

	-- The module's own sum, so each recheck lands on its slice's time to the bit
	local interval: number = 1 / harness.server.antiEsp.hiddenRate
	local first: number = 0 + interval
	local after: number = MOVED + interval

	-- Each slice's time and whether it tests the pair, the move made just before the slice at MOVED
	local slices: { { number | boolean } } = {
		{ 0, true },
		{ MOVED, true },
		{ first, false },
		{ after, true },
		{ after + interval / 2, false },
		{ after + interval, true },
	}

	for _, slice: { number | boolean } in slices do
		local now: number = slice[1] :: number
		local tested: boolean = slice[2] :: boolean

		AntiEsp.isHidden(viewer, target)
		if now == MOVED then
			AntiEsp.moved(target)
		end

		harness:slice(now)

		if (#harness.rays == 5) ~= tested or (#harness.rays ~= 0 and #harness.rays ~= 5) then
			return false, `The slice at {now} s cast {#harness.rays} rays, where a test was {tested}`
		end
	end

	return true, nil
end
