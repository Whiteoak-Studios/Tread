--[[
    With the slice not running whole, as it starts, its timers, walks and
    drains read no clock and run to the end past the deadline, a slice
    reads the clock as often as before, and that slice counts as a cut
    though nothing in it stopped but its tests
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local WALKED: vector = vector.create(5, 0, 0) -- Past the example's 4-stud retest
local MEASURED: number = 2 -- Seconds on, when both held sleepers' timers fall due, the example's 2 s hold past 0 s
local LATE_READ: number = 2 -- The late slice's first read after its deadline's, the one its tests begin at

-- The late slice's reads by today's rules: its deadline, its tests' start, and the first check of the two heaps it
-- finds waiting, the sleepers' and the hidden players', each of which stops there
local LATE_READS: number = 4
local WAITING: number = 3 -- The sleepers it lets wait all the same: both held ones and the walked-to one

-- Each body's name, kind and place, and whether rays to it are blocked from the second slice on
local BODIES: { { name: string, kind: string, at: vector, walled: boolean } } = {
	{ name = "Hidden", kind = "Player", at = vector.create(0, 0, -30), walled = true },
	{ name = "Seen", kind = "Player", at = vector.create(20, 0, 0), walled = false },
	{ name = "Held", kind = "Sleeper", at = vector.create(-30, 0, 0), walled = true },
	{ name = "Kept", kind = "Sleeper", at = vector.create(0, 0, 30), walled = true },
	{ name = "Walked", kind = "Sleeper", at = vector.create(30, 0, 30), walled = false },
}

-- The next slice's tests and rays at each body, by today's rules, of what the late one let wait: both held sleepers
-- from their timers, still held, the walked-to sleeper from its viewer's walk, the hidden player from the near queue
-- and the seen one from the visible queue
local RAYS: { [string]: number } = { Hidden = 6, Seen = 1, Held = 3, Kept = 3, Walked = 1 }
local TESTS: number = 5
local HIDDEN_RESULTS: number = 1
local READS: number = 2 + 2 * TESTS -- Its deadline, its tests' start, and before and after each test

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	-- 1) The refusals: a clock that is no function, and a switch that is no boolean
	local Unstarted: any = Environment.load(HARNESS)
	local refused: boolean, why: string = Refuses("clock as a function", function ()
		Unstarted.new(nil, "soon" :: any)
	end)
	if not refused then
		return false, `A start on a clock that is no function went another way: {why}`
	end

	for _, value: any in { "on", 1, {} } do
		refused, why = Refuses("useWhole takes true or false", AntiEsp.useWhole, value)
		if not refused then
			return false, `AntiEsp.useWhole of {value} went another way: {why}`
		end
	end

	if AntiEsp.wholeOn() then
		return false, "A slice ran whole before anything set it to"
	end

	-- 2) A viewer with players and sleepers, and a bot viewer with one sleeper of its own that walks
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local walker: any = harness:viewer("Walker", nil)
	local slots: { [string]: number } = {}
	local feet: { [number]: vector } = {}

	for _, body in BODIES do
		local slot: number = harness:body(body.kind, body.at)
		slots[body.name] = slot
		feet[slot] = body.at
	end

	-- A ray is blocked when it ends at a walled body
	local walled: { [string]: boolean } = { Hidden = true }
	harness.wall = function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		for _, body in BODIES do
			local offset: vector = finish - body.at
			if walled[body.name] and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				return true
			end
		end

		return false
	end

	local function ask()
		for _, name: string in { "Hidden", "Seen", "Held", "Kept" } do
			AntiEsp.isHidden(viewer, slots[name])
		end

		AntiEsp.isHidden(walker, slots.Walked)
	end

	-- Every pair tested at 0 s, the sleepers seen; then both of the viewer's sleepers walled and made due, so their
	-- retest at 0.1 s holds them on timers ending 2 s after they were seen
	ask()
	harness:slice(0)

	for _, body in BODIES do
		walled[body.name] = body.walled
	end

	AntiEsp.moved(slots.Held)
	AntiEsp.moved(slots.Kept)
	ask()
	harness:slice(0.1)

	ask()
	walker.position = WALKED

	local tests: number, hiddenResults: number, failOpens: number = AntiEsp.counts()
	AntiEsp.lying()

	-- 3) The late slice, whose clock is past its deadline from its first read after the deadline's on: its timers,
	-- walks and drains let everything due wait all the same, and it tests nothing
	harness:sliceOn(clock, MEASURED, LATE_READ)

	local lateTests: number, waiting: number = AntiEsp.lying()
	if clock.reads ~= LATE_READS then
		return false, `The late slice read the clock {clock.reads} times, where today's rules read it {LATE_READS}`
	elseif #harness.rays ~= 0 or lateTests ~= 0 then
		return false, `The late slice cast {#harness.rays} rays past its deadline`
	elseif waiting ~= WAITING then
		return false, `The late slice let {waiting} sleepers wait, not the {WAITING} its timers and walk reached`
	elseif AntiEsp.cuts() ~= 1 then
		return false, `The slice whose tests began past its deadline counted {AntiEsp.cuts()} cuts, not 1`
	end

	-- 4) The next slice, at the same time, tests what the late one let wait
	harness:sliceOn(clock, MEASURED)

	if clock.reads ~= READS then
		return false, `The next slice read the clock {clock.reads} times, where today's rules read it {READS}`
	elseif AntiEsp.cuts() ~= 1 then
		return false, `A slice inside its deadline counted a cut, {AntiEsp.cuts()} in all`
	end

	for name: string, expected: number in RAYS do
		local slot: number = slots[name]
		local count: number = 0

		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet[slot]
			if math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				count += 1
			end
		end

		if count ~= expected then
			return false, `The next slice cast {count} rays at {name}, not {expected}`
		end
	end

	local nowTests: number, nowHidden: number, nowFailOpens: number = AntiEsp.counts()
	local lyingTests: number, lyingWaiting: number = AntiEsp.lying()

	if nowTests - tests ~= TESTS or nowHidden - hiddenResults ~= HIDDEN_RESULTS or nowFailOpens ~= failOpens then
		return false, `The two slices counted {nowTests - tests} tests and {nowHidden - hiddenResults} hidden`
	elseif lyingTests ~= WAITING or lyingWaiting ~= 0 then
		return false, `The next slice tested {lyingTests} sleepers and left {lyingWaiting} waiting`
	end

	-- The verdicts the relay's next run finds
	ask()
	if not AntiEsp.isHidden(viewer, slots.Hidden) or AntiEsp.isHidden(viewer, slots.Seen) then
		return false, "The players' verdicts after the slices were not hidden and seen"
	elseif AntiEsp.reason(viewer.key, slots.Held) ~= "Hold" or AntiEsp.reason(viewer.key, slots.Kept) ~= "Hold" then
		return false, "The viewer's walled sleepers were not still held"
	elseif AntiEsp.reason(walker.key, slots.Walked) ~= "Clear" then
		return false, "The walker's sleeper was not seen on its retest"
	end

	return true, nil
end
