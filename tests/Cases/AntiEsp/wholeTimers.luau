--[[
    Running whole, a slice's sleepers' timers stop at the deadline, read
    before each, the cut slice testing nothing; the next slice tests the
    oldest held sleepers its timers took before taking the rest, oldest
    first, which the slice after it tests
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
-- Where each sleeper lies, far enough apart that no ray to one ends at another
local PLACES: { vector } = {
	vector.create(-30, 0, 0),
	vector.create(0, 0, 30),
	vector.create(30, 0, 0),
	vector.create(0, 0, -30),
}
local SEEN: { number } = { 0.1, 0.2, 0.3, 0.4 } -- When each sleeper is first seen, so their holds end in that order
local RETESTED: number = 0.5 -- When all four are retested walled, inside the example's 2 s hold, so each is held
local CUT: number = 3 -- Past every hold's end, so each retest after it hides its sleeper
local NEXT: number = 3.05 -- Begun at the walks after the timers' cut, so its tests come before its timers
local LAST: number = 3.1
local LATE_READ: number = 4 -- The cut slice's deadline, two timers, and then the read that finds it passed
local OLDEST: number = 2 -- The timers the cut slice takes before that read

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp
	local box: any = harness.shared.step.lyingBox

	AntiEsp.useWhole(true)
	if not AntiEsp.wholeOn() then
		return false, "AntiEsp.wholeOn read false after useWhole(true)"
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local sleepers: { number } = {}
	local heads: { vector } = {}

	-- Facing 0, each lies along -Z with its head half the box's length that way
	for index: number, at: vector in PLACES do
		sleepers[index] = harness:body("Sleeper", at)
		heads[index] = vector.create(at.x, box.lift, at.z - box.length / 2)
	end

	local function ask(count: number)
		for index: number = 1, count do
			AntiEsp.isHidden(viewer, sleepers[index])
		end
	end

	-- Which sleepers a slice cast at, each by its head ray
	local function tested(): { [number]: boolean }
		local found: { [number]: boolean } = {}
		for index: number, head: vector in heads do
			if harness:endingAt(head) > 0 then
				found[index] = true
			end
		end

		return found
	end

	-- Each seen in its own slice, then all four retested walled, so each waits on a timer ending 2 s after it was seen
	for index: number, now: number in SEEN do
		ask(index)
		harness:slice(now)
	end

	harness.wall = Harness.solid
	for _, sleeper: number in sleepers do
		AntiEsp.moved(sleeper)
	end

	ask(#sleepers)
	harness:slice(RETESTED)

	for index: number, sleeper: number in sleepers do
		if AntiEsp.reason(viewer.key, sleeper) ~= "Hold" then
			return false, `Sleeper {index}, retested walled inside its hold, was not held`
		end
	end

	-- The cut slice: its timers stop at the read that finds the deadline passed, after the oldest two, and it tests
	-- nothing, its clock past the deadline from then on
	AntiEsp.lying()
	ask(#sleepers)
	harness:sliceOn(clock, CUT, LATE_READ)

	local lyingTests: number, waiting: number = AntiEsp.lying()
	if #harness.rays ~= 0 or lyingTests ~= 0 then
		return false, `The slice cut in its timers cast {#harness.rays} rays`
	elseif waiting ~= OLDEST then
		return false, `The slice cut in its timers let {waiting} sleepers wait, not the {OLDEST} it took`
	elseif AntiEsp.cuts() ~= 1 then
		return false, `The slice cut in its timers counted {AntiEsp.cuts()} cuts, not 1`
	end

	-- Each later slice's retests, the oldest two in the next and the rest in the one after
	for _, step: { any } in { { NEXT, true }, { LAST, false } } do
		ask(#sleepers)
		harness:sliceOn(clock, step[1])

		local found: { [number]: boolean } = tested()
		for index: number = 1, #sleepers do
			if (found[index] == true) ~= ((index <= OLDEST) == step[2]) then
				return false, `The slice at {step[1]} s retested sleeper {index} {found[index] == true}`
			end
		end
	end

	if AntiEsp.cuts() ~= 1 then
		return false, `A slice that ran to its end counted a cut, {AntiEsp.cuts()} in all`
	end

	-- Every sleeper retested past its hold, so each is hidden now
	for index: number, sleeper: number in sleepers do
		if not AntiEsp.isHidden(viewer, sleeper) then
			return false, `Sleeper {index} was not hidden once its timer had been taken`
		end
	end

	return true, nil
end
