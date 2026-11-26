--[[
    AntiEsp.near counts a near hidden pair's rechecks and the seconds from
    each one's test before, and no first, far, visible, held or failed-open
    test, alike in process and on workers when the slices come evenly
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64 -- Seconds between even slices: 3 to a near recheck at 30 Hz, 7 to a far one at 10 Hz
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
	-- Five targets over 100 even slices, where a worker's test settles on the slice an in-process one runs in. The near
	-- hidden one is first tested at 0 and rechecked at 3 to 99, 33 rechecks. The revealed one is rechecked at 3, 6 and
	-- 9, its wall opens before 10, and its test at 12 finds it visible. The held one is seen at 0, closed before 30,
	-- held at 32 and 64 inside the 1 s hold, hidden at 96 and rechecked at 99. Each gap is 3 slices, so 37 rechecks and
	-- 111 slices. Its 65 tests are the near hidden one's 34, the far one's 15 at every 7th slice, the visible one's 4
	-- at every 32nd, the revealed one's 7, at 44 and 76 the last two, and the held one's 5
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
			{ slice = 12, target = 4, reason = "Clear" },
			{ slice = 32, target = 5, reason = "Hold" },
			{ slice = 64, target = 5, reason = "Hold" },
			{ slice = 96, target = 5, reason = "Hidden" },
		},
		checks = { 37, 37 },
		seconds = { 111 * STEP, 111 * STEP },
		tests = { 65, 65 },
		failOpens = 0,
	},

	-- A near hidden pair rechecked at 3 and 6, every slice from 8 to 16 cut before its tests, so the ask after 16 finds
	-- it 10 slices untested, past the 0.15 s fail-open. Its retest, at 17 in process and landing at 18 on workers, is
	-- no recheck, and the next, 3 slices on, is one. Its 5 tests are at 0, 3, 6, the retest and that one
	{
		name = "failed-open",
		targets = { { z = -200, blocked = true } },
		times = even(22),
		cut = { 8, 16 },
		asked = true,
		reasons = {},
		checks = { 3, 3 },
		seconds = { 9 * STEP, 9 * STEP },
		tests = { 5, 5 },
		failOpens = 1,
	},

	-- Slices at 0, 1, 2 and 2.5 steps. In process the recheck runs at 2.5, the first slice past 1/30 s. On workers it
	-- is packed at 2, reaching a step ahead, and settles on that reach, 3 steps, as it lands at 2.5, so its gap runs
	-- from its first test's reach to its own
	{
		name = "uneven",
		targets = { { z = -200, blocked = true } },
		times = { 0, STEP, 2 * STEP, 2.5 * STEP },
		asked = true,
		reasons = {},
		checks = { 1, 1 },
		seconds = { 2.5 * STEP, 3 * STEP },
		tests = { 2, 2 },
		failOpens = 0,
	},

	-- Slices at 0, 1, 2, 12 and 13 steps, asked only before the first. On workers the recheck packed at 2 comes back at
	-- 12, past the fail-open time from its send, so it is given up and packed again, reaching a relay tick ahead, and
	-- lands at 13: one recheck, settled at 12 steps and a relay tick. In process it runs at 12
	{
		name = "given-up",
		targets = { { z = -200, blocked = true } },
		times = { 0, STEP, 2 * STEP, 12 * STEP, 13 * STEP },
		asked = false,
		reasons = {},
		checks = { 1, 1 },
		seconds = { 12 * STEP, 12 * STEP + LEAD },
		tests = { 2, 2 },
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
