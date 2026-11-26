--[[
    Running whole with verdict memory on, a recheck a kept answer could
    settle with no ray waits at a cut as any test does: the slice whose
    deadline comes at its tests settles nothing, and the next slice, begun
    at its tests, settles it from its kept answer, casting no ray
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local WALLED: vector = vector.create(0, 0, -30) -- Inside the example's 250-stud near radius, so rechecked once a server tick
local KEPT_AT: number = 0.05 -- Its first recheck, at the next server tick, which its kept answer settles
local CUT_AT: number = 0.1 -- Its next, in the cut slice
local LATE_READ: number = 3 -- The deadline, the near queue's entry, then the tests' start, found passed
local NEXT: number = 0.11
local RAYS: number = 6 -- Its first test's, every one blocked

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	AntiEsp.useMemory(true)
	AntiEsp.useWhole(true)

	-- A still viewer and a still target behind a wall, so each recheck can take its last answer
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local walled: number = harness:body("Player", WALLED)
	harness.wall = Harness.solid

	-- Its first test aims and casts, and its first recheck takes the kept answer with no ray
	AntiEsp.isHidden(viewer, walled)
	harness:slice(0)
	harness:remembered()

	if #harness.rays ~= RAYS then
		return false, `The first test cast {#harness.rays} rays, not every one of its {RAYS}`
	end

	AntiEsp.isHidden(viewer, walled)
	harness:sliceOn(clock, KEPT_AT)

	local kept: number = harness:remembered()
	if kept ~= 1 or #harness.rays ~= 0 then
		return false, `The first recheck took {kept} kept answers and cast {#harness.rays} rays`
	end

	-- The cut slice drains the recheck, and its deadline comes as its tests begin: nothing settled, kept or not
	AntiEsp.isHidden(viewer, walled)
	local tests: number = AntiEsp.counts()
	harness:sliceOn(clock, CUT_AT, LATE_READ)

	kept = harness:remembered()
	if kept ~= 0 or #harness.rays ~= 0 or AntiEsp.counts() ~= tests then
		return false, `The cut slice settled {AntiEsp.counts() - tests} tests, {kept} of them kept answers`
	elseif AntiEsp.cuts() ~= 1 then
		return false, `The slice whose tests began past its deadline counted {AntiEsp.cuts()} cuts`
	end

	-- The next slice begins at its tests and settles the recheck from its kept answer
	harness:sliceOn(clock, NEXT)

	kept = harness:remembered()
	if kept ~= 1 or #harness.rays ~= 0 or AntiEsp.counts() ~= tests + 1 then
		return false, `The slice after the cut took {kept} kept answers and cast {#harness.rays} rays`
	elseif not AntiEsp.isHidden(viewer, walled) then
		return false, "The walled target was sent once its kept answer was taken after the cut"
	end

	return true, nil
end
