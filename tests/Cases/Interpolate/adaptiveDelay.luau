--[[
    The render delay starts at interpolation.delay, grows by how late a
    block comes up to interpolation.delayMax, never drops for an early one,
    and eases back to its floor no faster than the time scale's headroom
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local TOLERANCE: number = 1e-9

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local settings: { [string]: number } = viewer.settings
	local ease: number = settings.scaleMax - 1 -- Seconds the delay may shrink a second

	local function check(expected: number, when: string): string?
		local delay: number = Interpolate.delay()
		if math.abs(delay - expected) > TOLERANCE then
			return `The delay was {delay} s {when}, not {expected}`
		end

		return nil
	end

	local failure: string? = check(settings.delay, "before any block")
	if failure then
		return false, failure
	end

	-- Blocks at once are early, not late
	for tick: number = 100, 104 do
		viewer.send({ tick = tick })
	end

	Interpolate.frame(0)
	failure = check(settings.delay, "after five blocks at once")
	if failure then
		return false, failure
	end

	-- On time, one relay interval after the last
	Interpolate.frame(0.05)
	viewer.send({ tick = 105 })
	failure = check(settings.delay, "after a block on time")
	if failure then
		return false, failure
	end

	-- 0.04 s late
	Interpolate.frame(0.05)
	Interpolate.frame(0.04)
	viewer.send({ tick = 106 })
	failure = check(settings.delay + 0.04, "after a block 0.04 s late")
	if failure then
		return false, failure
	end

	Interpolate.frame(0.2)
	failure = check(settings.delay + 0.04 - ease * 0.2, "0.2 s after it")
	if failure then
		return false, failure
	end

	Interpolate.frame(2)
	failure = check(settings.delay, "2 s later, at its floor")
	if failure then
		return false, failure
	end

	-- Seconds late, which the delay covers only up to its ceiling
	Interpolate.frame(0.5)
	viewer.send({ tick = 107 })
	failure = check(settings.delayMax, "after a block seconds late")
	if failure then
		return false, failure
	end

	viewer.send({ tick = 108 })
	failure = check(settings.delayMax, "after an early block")
	if failure then
		return false, failure
	end

	Interpolate.frame(1)
	failure = check(settings.delayMax - ease, "1 s after the ceiling")
	if failure then
		return false, failure
	end

	return true, nil
end
