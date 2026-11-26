--[[
    AntiEsp.near counts a near hidden pair's rechecks and the seconds from
    each one's test before, and no first, far, visible, held or failed-open
    test, in process and on workers, each on the clock it was settled on
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64 -- Seconds between even slices: 3 or 4 to a tick at 20 Hz, 7 to a far recheck at 10 Hz
local LATE: number = 2 -- A cut slice's first stand-in clock read past its deadline, the one before its first test
local PATHS: { string } = { "in process", "on workers" }
local TOTALS: { string } = { "near rechecks", "seconds of near rechecks", "tests", "fail-opens" }

local Example: any = Environment.load(EXAMPLE)
local LEAD: number = 1 / Example.shared().rates.relay -- Seconds a packing slice reaches ahead at most, a relay tick

-- A target on the line ahead of or behind the viewer at the origin, whether its rays start blocked, and the slice
-- before which its wall flips, if it does
type Target = { z: number, blocked: boolean, flip: number? }

-- A target's reason read after a slice, which shows the scenario took the path it is built for
type Reason = { slice: number, target: number, reason: string }

-- One scenario and what each path gives, in process then on workers
type Scenario = {
	name: string,
	targets: { Target },
	times: { number }, -- Each slice's time, the slices counted from 0
	cut: { number }?, -- The first and last slice whose deadline passes before its first test
	asked: boolean, -- Every pair asked after each slice, or only before the first
	reasons: { Reason },
	checks: { number },
	seconds: { number },
	tests: { number },
	failOpens: number,
}

-- Times for count even slices from 0
local function even(count: number): { number }
	local times: { number } = table.create(count)
	for slice: number = 0, count - 1 do
		times[slice + 1] = slice * STEP
	end

	return times
end

local SCENARIOS: { Scenario } = {
	-- Five targets over 100 even slices, slice k in tick floor(5k / 16), so tick n's first slice is ceil(16n / 5): 0,
	-- 4, 7, 10, 13, 16, 20 and so on. The near hidden one is first tested at 0 and rechecked at each tick's first slice
	-- to 96, 30 rechecks. The revealed one is rechecked at 4 and 7, its wall opens before 10, and its test there finds
	-- it visible. The held one is seen at 0, closed before 30, held at 32 and 64 inside the 1 s hold and hidden at 96,
	-- tick 30's first, so in process its next test would be tick 31's, at 100. In process that is 32 rechecks over 103
	-- slices, and 60 tests: the near hidden one's 31, the far one's 15 at every 7th slice, the visible one's 4 at every
	-- 32nd, the revealed one's 6, at 42 and 74 the last two, and the held one's 4. On workers each settles on its
	-- reach, a slice past its packing but the first, so the near hidden one's gaps span 97 slices and the revealed
	-- one's 8; the held one's test at 96 was packed at 95, in tick 29, so it lands due and is rechecked a slice on: 33
	-- rechecks over 106 slices, and 61 tests
	{
		name = "mixed",
		targets = {
			{ z = -200, blocked = true },
			{ z = -300, blocked = true },
			{ z = 200, blocked = false },
			{ z = -100, blocked = true, flip = 10 },
			{ z = 100, blocked = false, flip = 30 },
		},
		times = even(100),
		asked = true,
		reasons = {
			{ slice = 11, target = 4, reason = "Clear" },
			{ slice = 32, target = 5, reason = "Hold" },
			{ slice = 64, target = 5, reason = "Hold" },
			{ slice = 96, target = 5, reason = "Hidden" },
		},
		checks = { 32, 33 },
		seconds = { 103 * STEP, 106 * STEP },
		tests = { 60, 61 },
		failOpens = 0,
	},

	-- A near hidden pair rechecked at 4 and 7, every slice from 8 to 17 cut before its tests. In process the ask after
	-- 17 finds it 10 slices untested, past the 0.15 s fail-open, and its retest at 18 is no recheck, and the next, at
	-- tick 6's first slice, 20, is one. On workers its test at 7 settled at 8, so the ask after 18 fails it open with
	-- that slice's packing out; its retest is packed at 19 and lands due at 20, packed again there and landing at 21,
	-- a recheck. Its 5 tests are at 0, 4, 7, the retest and that one
	{
		name = "failed-open",
		targets = { { z = -200, blocked = true } },
		times = even(22),
		cut = { 8, 17 },
		asked = true,
		reasons = {},
		checks = { 3, 3 },
		seconds = { 9 * STEP, 9 * STEP },
		tests = { 5, 5 },
		failOpens = 1,
	},

	-- Slices at 0, 1, 2, 3.5 and 4.5 steps. In process the recheck runs at 3.5, tick 1's first slice. On workers it is
	-- packed there too, reaching the step and a half since the slice before, and settles on that reach, 5 steps, as it
	-- lands at 4.5, so its gap runs from its first test's reach to its own
	{
		name = "uneven",
		targets = { { z = -200, blocked = true } },
		times = { 0, STEP, 2 * STEP, 3.5 * STEP, 4.5 * STEP },
		asked = true,
		reasons = {},
		checks = { 1, 1 },
		seconds = { 3.5 * STEP, 5 * STEP },
		tests = { 2, 2 },
		failOpens = 0,
	},

	-- Slices at 0, 1, 4, 14 and 15 steps, asked only before the first. On workers the recheck packed at 4, tick 1's,
	-- comes back at 14, past the fail-open time from its send, so it is given up and packed again, reaching a relay
	-- tick ahead, and lands at 15: one recheck, settled at 14 steps and a relay tick. In process it runs at 4 and again
	-- at 14, in tick 4
	{
		name = "given-up",
		targets = { { z = -200, blocked = true } },
		times = { 0, STEP, 4 * STEP, 14 * STEP, 15 * STEP },
		asked = false,
		reasons = {},
		checks = { 2, 1 },
		seconds = { 14 * STEP, 14 * STEP + LEAD },
		tests = { 3, 2 },
		failOpens = 0,
	},
}

-- One scenario on one path, with workers when given: why it went another way than it is built for, and its totals
local function run(scenario: Scenario, workers: number?): (string?, { number })
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local clock: any = Harness.clock()
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end, clock.read)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made

	-- Whether a ray is blocked, by where it ends along z, each target's own
	local closed: { [number]: boolean } = {}
	local function wall(origin: vector, direction: vector): boolean
		return closed[math.round((origin + direction).z)] == true
	end

	harness.wall = wall
	if pool then
		pool.wall = wall
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local slots: { number } = {}
	for index: number, target: Target in scenario.targets do
		slots[index] = harness:body("Player", vector.create(0, 0, target.z))
		closed[target.z] = target.blocked
	end

	local function ask()
		for _, slot: number in slots do
			AntiEsp.isHidden(viewer, slot)
		end
	end

	ask()

	for at: number, now: number in scenario.times do
		local slice: number = at - 1
		for _, target: Target in scenario.targets do
			if target.flip == slice then
				closed[target.z] = not target.blocked
			end
		end

		local late: number? = nil
		local cut: { number }? = scenario.cut
		if cut ~= nil and slice >= cut[1] and slice <= cut[2] then
			late = LATE
		end

		harness:sliceOn(clock, now, late)

		if scenario.asked then
			ask()
		end

		for _, reason: Reason in scenario.reasons do
			if reason.slice == slice then
				local found: string = AntiEsp.reason(viewer.key, slots[reason.target])
				if found ~= reason.reason then
					return `target {reason.target} was {found} after slice {slice}, not {reason.reason}`, {}
				end
			end
		end
	end

	local checks: number, seconds: number = AntiEsp.near()
	local tests: number, _, failOpens: number = AntiEsp.counts()

	return nil, { checks, seconds, tests, failOpens }
end

return function (): (boolean, string | nil)
	for _, scenario: Scenario in SCENARIOS do
		for path: number, name: string in PATHS do
			local workers: number? = path == 2 and WORKERS or nil
			local failure: string?, totals: { number } = run(scenario, workers)
			if failure ~= nil then
				return false, `The {scenario.name} scenario {name}: {failure}`
			end

			local wanted: { number } =
				{ scenario.checks[path], scenario.seconds[path], scenario.tests[path], scenario.failOpens }

			for index: number, label: string in TOTALS do
				if totals[index] ~= wanted[index] then
					return false,
						`The {scenario.name} scenario {name} gave {totals[index]} {label}, not {wanted[index]}`
				end
			end
		end
	end

	return true, nil
end
