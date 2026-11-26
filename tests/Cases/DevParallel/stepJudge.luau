--[[
    ParallelStep's judge: figures that pass give a line a probe a clone and
    no problem, with times never judged, and each planted fault gives one
    problem naming its probe, its clone and what differed
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local STEP: string = "dev/Server/Parallel/Step.luau"
local WORKERS: number = 2
local WAIT: number = 30 -- Seconds the figures say each probe's answers had
local QUERIES: number = 5040 -- Each kind's queries, 90 slots of 56
local HITS: number = 100
local BOXES: number = 2000
local OVERLAPPING: number = 900
local PLAN: number = 0xABC -- The main thread's plan hash
local SECTION_HASH: number = 0x16 -- The battery's second section's
local SEPARATOR: string = " | "

-- Each probe's lines as the judge gives them for the passing figures, every clone alike but for its times
local KINDS: string = table.concat({
	"ray 5040 queries, 0 differing, 0 sign only, 0 missing, 100 hits",
	"sweep 5040 queries, 0 differing, 0 sign only, 0 missing, 100 hits",
	"sphere 5040 queries, 0 differing, 0 sign only, 0 missing, 100 hits",
	"rest 5040 queries, 0 differing, 0 sign only, 0 missing, 100 hits",
}, "; ")

local LOADED: string =
	"LoadedConfig ok, LoadedEngine ok, LoadedWorld ok, LoadedBuiltins ok, LoadedQueries ok, BuiltCasts ok, BuiltWorld ok"
local ARM: string = "2000 boxes, 0 differing, 900 overlapping, 0 missing, first difference none"

local LINES: { string } = {
	`ParallelStep P9 clone 1: {LOADED}; include list the same, 2 in its own list against 2 sent`,
	`ParallelStep P9 clone 2: {LOADED}; include list the same, 2 in its own list against 2 sent`,
	"ParallelStep P2 main: 90 slots of 2560 parts, plan hash 00000abc, cast 100.000 ms; hits ray 100 of 5040, "
		.. "sweep 100 of 5040, sphere 100 of 5040, rest 100 of 5040",
	`ParallelStep P2 clone 1: plan hash 00000abc; {KINDS}; first difference none; cast 120.000 ms against the main thread's 100.000 ms`,
	`ParallelStep P2 clone 2: plan hash 00000abc; {KINDS}; first difference none; cast 340.000 ms against the main thread's 100.000 ms`,
	"ParallelStep P7 main: 2000 boxes, 900 overlapping",
	`ParallelStep P7 clone 1: serial {ARM}; parallel {ARM}`,
	`ParallelStep P7 clone 2: serial {ARM}; parallel {ARM}`,
	"ParallelStep P3 main: 2 sections, 7168 values, hash 00000021, timing loop 12.000 ms",
	"ParallelStep P3 clone 1: 2 sections, every section matches; timing loop 40.000 ms against the main thread's 12.000 ms",
	"ParallelStep P3 clone 2: 2 sections, every section matches; timing loop 3.000 ms against the main thread's 12.000 ms",
}

-- A planted fault: what it changes in passing figures, and the words its one problem must hold
type Fault = {
	label: string,
	plant: (figures: any) -> (),
	needles: { string },
}

-- Each kind's tally at that many hits, nothing differing
local function tallies(hits: number): { any }
	local made: { any } = {}
	for _, kind: string in { "ray", "sweep", "sphere", "rest" } do
		table.insert(made, { kind = kind, queries = QUERIES, differing = 0, signOnly = 0, missing = 0, hits = hits })
	end

	return made
end

local function overlapTally(): any
	return { boxes = BOXES, differing = 0, overlapping = OVERLAPPING, missing = 0 }
end

-- The battery as one copy ran it, two sections of it, timed at that many ms
local function battery(loopMs: number): any
	return {
		sections = {
			{ name = "math.lerp", width = 1, records = 4096, hash = 0x0B },
			{ name = "Part.CFrame written", width = 12, records = 256, hash = SECTION_HASH },
		},
		values = 7168,
		hash = 0x21,
		loopMs = loopMs,
		loopValue = 1000,
	}
end

-- Figures that pass, built fresh, each clone's times other than the main thread's
local function passing(loads: { string }): any
	local everyLoad: { [string]: unknown } = {}
	for _, attribute: string in loads do
		everyLoad[attribute] = true
	end

	return {
		workers = WORKERS,
		wait = WAIT,
		loads = {
			loads = { table.clone(everyLoad), table.clone(everyLoad) },
			checks = { { same = true, own = 2, received = 2 }, { same = true, own = 2, received = 2 } },
			failures = {},
		},
		casts = {
			slots = 90,
			parts = 2560,
			hash = PLAN,
			seconds = 0.1,
			tallies = tallies(HITS),
			casts = {
				{ hash = PLAN, seconds = 0.12, tallies = tallies(HITS) },
				{ hash = PLAN, seconds = 0.34, tallies = tallies(HITS) },
			},
			failures = {},
		},
		overlaps = {
			boxes = BOXES,
			overlapping = OVERLAPPING,
			arms = {
				{ name = "serial", tallies = { overlapTally(), overlapTally() }, failures = {} },
				{ name = "parallel", tallies = { overlapTally(), overlapTally() }, failures = {} },
			},
		},
		battery = { main = battery(12), results = { battery(40), battery(3) }, failures = {} },
	}
end

local FAULTS: { Fault } = {
	{
		label = "a clone that failed to load",
		plant = function (figures: any)
			figures.loads.loads[2].LoadedQueries = "Requested module experienced an error while loading"
		end,
		needles = { "P9 clone 2", "LoadedQueries failed: Requested module experienced an error" },
	},
	{
		label = "an include list that differs",
		plant = function (figures: any)
			figures.loads.checks[1] = { same = false, own = 3, received = 2 }
		end,
		needles = { "P9 clone 1", "include list differs, 3 in its own list against 2 sent" },
	},
	{
		label = "a plan hash that differs",
		plant = function (figures: any)
			figures.casts.casts[2].hash = 0xDEF
		end,
		needles = { "P2 clone 2", "plan hash 00000def against the main thread's 00000abc" },
	},
	{
		label = "one differing query in one kind",
		plant = function (figures: any)
			local sweep: any = figures.casts.casts[1].tallies[2]
			sweep.differing = 1
			sweep.first = "query 7 position.x: ours 4000000000000000, theirs 4000000000000001"
		end,
		needles = { "P2 clone 1", "sweep has 1 of 5040 queries differing", "query 7 position.x" },
	},
	{
		label = "a kind with no hits on the main side",
		plant = function (figures: any)
			figures.casts.tallies[4].hits = 0
			for _, cast: any in figures.casts.casts do
				cast.tallies[4].hits = 0
			end
		end,
		needles = { "P2 main", "rest hit nothing in 5040 queries" },
	},
	{
		label = "a clone silent on P2",
		plant = function (figures: any)
			figures.casts.casts[2] = nil
		end,
		needles = { "P2", "no answer from clone 2 within 30 s" },
	},
	{
		label = "a P7 arm with an error",
		plant = function (figures: any)
			local arm: any = figures.overlaps.arms[2]
			arm.tallies[1] = nil
			arm.failures[1] = "Property Part.Size is not safe to write in parallel"
		end,
		needles = { "P7 clone 1 parallel", "failed: Property Part.Size is not safe to write in parallel" },
	},
	{
		label = "a P7 run where every box overlaps",
		plant = function (figures: any)
			figures.overlaps.overlapping = BOXES
			for _, arm: any in figures.overlaps.arms do
				for _, tally: any in arm.tallies do
					tally.overlapping = BOXES
				end
			end
		end,
		needles = { "P7 main", "every one of its 2000 boxes overlaps" },
	},
	{
		label = "a P3 section that differs",
		plant = function (figures: any)
			local result: any = figures.battery.results[2]
			result.sections[2].hash = SECTION_HASH + 1
			result.hash += 1
		end,
		needles = { "P3 clone 2", "Part.CFrame written: hash ours 00000016, theirs 00000017" },
	},
	{
		label = "a P3 timing loop that ended elsewhere, its stream's hash alike",
		plant = function (figures: any)
			figures.battery.results[1].loopValue = 999
		end,
		needles = { "P3 clone 1", "timing loop: ours ended at 1000, theirs 999" },
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local Work: any = loaded.require(server.Parallel.Work)

	-- The dev shared table stands in empty, since the judge reads nothing of it
	local results: { [any]: any } = { [shared.Dev.Config] = {} }
	local Step: any =
		Kit.loader(dataModel, { [server.Parallel.Step] = STEP }, results, loaded.require)(server.Parallel.Step)
	local loads: { string } =
		{ Work.CONFIG, Work.ENGINE, Work.WORLD, Work.BUILTINS, Work.QUERIES, Work.CASTS, Work.WORLD_BUILT }

	-- 1) Figures that pass give each line as the probe prints it and no problem, each clone timed otherwise
	local lines: { string }, problems: { string } = Step.judge(passing(loads))
	if #problems > 0 then
		return false, `Passing figures gave problems: {table.concat(problems, SEPARATOR)}`
	end

	for index: number, line: string in LINES do
		if lines[index] ~= line then
			return false, `Line {index} was "{lines[index]}", not "{line}"`
		end
	end

	if #lines ~= #LINES then
		return false, `The judge gave {#lines} lines, not {#LINES}`
	end

	-- 2) Each fault gives one problem holding its probe, its clone and what differed
	for _, fault: Fault in FAULTS do
		local figures: any = passing(loads)
		fault.plant(figures)

		local _, found: { string } = Step.judge(figures)
		if #found ~= 1 then
			return false, `{fault.label} gave {#found} problems: {table.concat(found, SEPARATOR)}`
		end

		for _, needle: string in fault.needles do
			if string.find(found[1], needle, 1, true) == nil then
				return false, `{fault.label} gave "{found[1]}", which does not name "{needle}"`
			end
		end
	end

	-- 3) A probe that never ran and a stop are problems of their own
	local short: any = passing(loads)
	short.battery = nil
	short.stopped = "it threw: a planted throw"

	local _, stopped: { string } = Step.judge(short)
	if table.concat(stopped, SEPARATOR) ~= "stopped short: it threw: a planted throw | P3 did not run" then
		return false, `A stop before P3 gave {table.concat(stopped, SEPARATOR)}`
	end

	return true, nil
end
