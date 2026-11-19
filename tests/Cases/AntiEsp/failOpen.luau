--[[
    A hidden player pair no slice has time to recheck turns visible once
    the fail-open time has passed since it was made, counted once, and its
    next test with every ray blocked hides it again with no hold
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local RETESTED: number = 0.31 -- When a slice first has time again
local INTERVAL: number = 0.1 -- The example's hidden recheck
local RECHECKS: number = 20

-- Each slice's time with no time to test, and whether the pair is hidden after it, past the example's 0.15 s
local STARVED: { { number | boolean } } = {
	{ 0.1, true },
	{ 0.15, true },
	{ 0.16, false },
	{ 0.3, false },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))

	-- Made at 0 s, the slice's time
	harness:slice(0, 0)
	if not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "The new pair was not hidden"
	end

	for _, step: { number | boolean } in STARVED do
		local now: number = step[1] :: number
		local hidden: boolean = step[2] :: boolean

		harness:slice(now, 0)

		if #harness.rays ~= 0 then
			return false, `A slice with no time cast {#harness.rays} rays`
		elseif Harness.AntiEsp.isHidden(viewer, target) ~= hidden then
			return false, `After the starved slice at {now} s the pair was not {hidden and "hidden" or "visible"}`
		end
	end

	local _, _, failOpens: number = Harness.AntiEsp.counts()
	if failOpens ~= 1 then
		return false, `The pair failed open {failOpens} times, not once`
	end

	harness:slice(RETESTED)
	if #harness.rays == 0 then
		return false, "The failed-open pair was not tested once there was time"
	elseif not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "The failed-open pair stayed visible after a test with every ray blocked"
	end

	-- Rechecked in time, it never fails open
	for tick: number = 1, RECHECKS do
		harness:slice(RETESTED + tick * INTERVAL)
		if not Harness.AntiEsp.isHidden(viewer, target) then
			return false, `The pair rechecked in time failed open on its recheck {tick}`
		end
	end

	return true, nil
end
