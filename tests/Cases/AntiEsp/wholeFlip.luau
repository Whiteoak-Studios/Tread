--[[
    Turned off after a cut, the slice runs today's order whole from the
    next slice, whatever the cut left: its timers, walks and drains read no
    clock and let everything due wait past the deadline; turned on again,
    it begins at its first step, as a slice after no cut does
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

local CUT_READ: number = 4 -- The deadline, the first two viewers measured, then the third's read, found passed
local OFF_READ: number = 2 -- The deadline, then the tests' start, found passed, as the walks read no clock while off
-- Those two and the sleepers' heap's first check under their share and again after the players' empty heaps, each
-- of which stops there
local OFF_READS: number = 4

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp
	local box: any = harness.shared.step.lyingBox

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

	-- Whether a slice retested exactly the sleepers named, each by its head ray
	local function retested(expected: { number }): boolean
		if #harness.rays ~= #expected then
			return false
		end

		for _, sleeper: number in expected do
			if harness:endingAt(heads[sleeper]) ~= 1 then
				return false
			end
		end

		return true
	end

	ask()
	harness:slice(0)

	viewers[1].position = EDGE
	viewers[2].position = PAST
	viewers[3].position = PAST

	-- On: the walk cut at the third viewer, so a whole slice would go on from the drains and walk from the third
	AntiEsp.useWhole(true)
	ask()
	harness:sliceOn(clock, 1, CUT_READ)

	if not retested({}) then
		return false, `The cut slice cast {#harness.rays} rays`
	end

	-- Off: the next slice walks every viewer from the first, past its deadline, and lets both sleepers wait
	AntiEsp.useWhole(false)
	AntiEsp.lying()
	ask()
	harness:sliceOn(clock, 1.1, OFF_READ)

	local _, waiting: number = AntiEsp.lying()
	if AntiEsp.wholeOn() then
		return false, "AntiEsp.wholeOn read true after useWhole(false)"
	elseif clock.reads ~= OFF_READS then
		return false, `The slice not running whole read the clock {clock.reads} times, not today's {OFF_READS}`
	elseif waiting ~= 2 then
		return false, `The slice not running whole let {waiting} sleepers wait, not both its walk reached`
	elseif not retested({}) then
		return false, `The slice not running whole cast {#harness.rays} rays past its deadline`
	end

	ask()
	harness:sliceOn(clock, 1.2)
	if not retested({ 2, 3 }) then
		return false, `The slice after cast {#harness.rays} rays, not at the two sleepers its walk let wait`
	end

	-- On again: no cut since, so the next slice begins at its timers and walks from the first viewer
	AntiEsp.useWhole(true)
	ask()
	harness:sliceOn(clock, 1.3)

	if not retested({}) then
		return false, `A whole slice with nothing due cast {#harness.rays} rays`
	elseif AntiEsp.cuts() ~= 2 then
		return false, `The cut slice and the late one counted {AntiEsp.cuts()} cuts`
	end

	return true, nil
end
