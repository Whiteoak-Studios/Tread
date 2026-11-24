--[[
    A hidden pair whose fail-open comes due while its answer is out with a
    worker, in a run that leaves its viewer out: a twin asked that run
    fails it open, drops the answer when it lands and packs it again, while
    the left one, kept by AntiEsp.passed, settles the answer and stays hidden
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local WALLED: vector = vector.create(0, 0, -30)
local SEEN: vector = vector.create(20, 0, 0)
local STARVED: number = 2 -- A slice's late read: the deadline, then its first item's, found passed, so it takes none

-- Each slice's time and late read before the left run: packed and landed, starved past 0.15 s, then packed again
local BEFORE: { { number } } = {
	{ 0, math.huge },
	{ 0.05, STARVED },
	{ 0.1, STARVED },
	{ 0.16, math.huge },
}

local LANDS_AT: number = 0.2 -- The slice its answer lands at, after the left run
local THEN: number = 0.25

type Twin = {
	harness: any,
	pool: any,
	clock: any,
	AntiEsp: any,
	left: any,
	other: any,
	walled: number,
	seen: number,
}

local function twin(): Twin
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local clock: any = Harness.clock()
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end, clock.read)
	Harness.AntiEsp.useWhole(true)

	local function wall(origin: vector, direction: vector): boolean
		local offset: vector = origin + direction - WALLED

		return math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH
	end

	harness.wall = wall
	override.made.wall = wall

	local _, left: any = harness:player("Left", vector.zero)
	local _, other: any = harness:player("Other", vector.create(0, 0, 50))

	return {
		harness = harness,
		pool = override.made,
		clock = clock,
		AntiEsp = Harness.AntiEsp,
		left = left,
		other = other,
		walled = harness:body("Player", WALLED),
		seen = harness:body("Player", SEEN),
	}
end

local function counts(side: Twin): (number, number)
	local tests: number, _, failOpens: number = side.AntiEsp.counts()

	return tests, failOpens
end

-- One run: the other viewer's ask, then the left viewer's ask of the walled pair or passed in its place
local function run(side: Twin, left: boolean): boolean?
	side.AntiEsp.isHidden(side.other, side.seen)

	if left then
		side.AntiEsp.passed(side.left, { side.walled }, 1)

		return nil
	end

	return side.AntiEsp.isHidden(side.left, side.walled)
end

return function (): (boolean, string | nil)
	local asked: Twin = twin()
	local passed: Twin = twin()
	local twins: { Twin } = { asked, passed }

	-- Packed at 0 s and landed hidden, untested through two starved slices, then packed again at 0.16 s
	for _, side: Twin in twins do
		for _, step: { number } in BEFORE do
			run(side, false)
			side.harness:sliceOn(side.clock, step[1], step[2])
		end
	end

	-- The left run, with that answer out: the asked twin fails the pair open, the left one keeps it hidden
	local answer: boolean? = run(asked, false)
	run(passed, true)

	local _, askedFailOpens: number = counts(asked)
	local _, passedFailOpens: number = counts(passed)
	if answer or askedFailOpens ~= 1 then
		return false, `The asked twin's ask past the fail-open counted {askedFailOpens} fail-opens, answer {answer}`
	elseif passedFailOpens ~= 0 or passed.AntiEsp.reason(passed.left.key, passed.walled) ~= "Hidden" then
		return false, `The left twin's pair counted {passedFailOpens} fail-opens in the run it was left out of`
	end

	-- The answer lands: dropped by the asked twin, whose fail-open restamped the pair, which it packs again; settled
	-- hidden by the left one, which packs nothing
	local sent: { number } = { #asked.pool.sends, #passed.pool.sends }
	local tests: { number } = {}
	tests[1] = counts(asked)
	tests[2] = counts(passed)

	for _, side: Twin in twins do
		side.harness:sliceOn(side.clock, LANDS_AT)
	end

	local askedTests: number = counts(asked)
	local passedTests: number = counts(passed)
	if askedTests ~= tests[1] or #asked.pool.sends ~= sent[1] + 1 then
		return false,
			`The asked twin settled {askedTests - tests[1]} landed answers and sent {#asked.pool.sends - sent[1]}`
	elseif passedTests ~= tests[2] + 1 or #passed.pool.sends ~= sent[2] then
		return false,
			`The left twin settled {passedTests - tests[2]} landed answers and sent {#passed.pool.sends - sent[2]}`
	end

	-- Its next ask: the asked twin's pair still sent as failed open, its new answer out; the left one's hidden and
	-- tested, with no fail-open
	answer = run(asked, false)
	local passedAnswer: boolean? = run(passed, false)
	_, askedFailOpens = counts(asked)
	_, passedFailOpens = counts(passed)

	if answer or not passedAnswer then
		return false, `The next ask found the asked twin's pair hidden {answer} and the left one's {passedAnswer}`
	elseif askedFailOpens ~= 1 or passedFailOpens ~= 0 then
		return false, `The twins counted {askedFailOpens} and {passedFailOpens} fail-opens at the next ask`
	end

	-- The asked twin's second answer lands hidden, and both then answer hidden
	for _, side: Twin in twins do
		side.harness:sliceOn(side.clock, THEN)
	end

	if not run(asked, false) or not run(passed, false) then
		return false, "The twins' walled pairs weren't both hidden once every answer had landed"
	end

	return true, nil
end
