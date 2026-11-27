--[[
    P10's judge: figures that pass give a line a source and a line a clone
    and no problem, each planted fault gives one problem naming its source
    or clone, and a stop before the clones answered names them all silent
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOUNDS: string = "dev/Server/Parallel/Bounds.luau"
local WORKERS: number = 2
local WAIT: number = 30 -- Seconds the figures say the clones' answers had
local ANSWERS: { number } = { 1, 0, 1, 1, 0, 0 } -- The main thread's bounds answers to the boxes each clone was sent
local VALUE_BYTES: number = 8
local UNSOUND_AT: string = "center (10.000, 2.500, -30.000), size (4.000, 5.000, 4.000)"
local SEPARATOR: string = " | "

-- The lines the judge gives for the passing figures, the sources' then the clones'
local LINES: { string } = {
	"ParallelBounds P7: 2000 boxes, 1200 settled (60.0%), 780 exact inside, 0 unsound, 20 Terrain-only",
	"ParallelBounds S3: 3000 boxes, 2250 settled (75.0%), 700 exact inside, 0 unsound, 0 Terrain-only; 45000 reads, "
		.. "3012 walkers, 12 dropped, 3 skipped, 0 failed",
	"ParallelBounds Spread150: 1500 boxes, 500 settled (33.3%), 1000 exact inside, 0 unsound, 4 Terrain-only; "
		.. "22000 reads, 1500 walkers, 0 dropped, 0 skipped, 1 failed",
	"ParallelBounds clone 1: 6 boxes compared, 0 differing, first difference none",
	"ParallelBounds clone 2: 6 boxes compared, 0 differing, first difference none",
}

-- A planted fault: what it changes in passing figures, and the words its one problem must hold
type Fault = {
	label: string,
	plant: (figures: any) -> (),
	needles: { string },
}

-- Answers as the probe keeps them, one f64 a box
local function answers(values: { number }): buffer
	local stream: buffer = buffer.create(#values * VALUE_BYTES)
	for index: number, value: number in values do
		buffer.writef64(stream, (index - 1) * VALUE_BYTES, value)
	end

	return stream
end

-- A recording's own counts, its boxes left empty since the judge never reads them
local function recording(name: string, recorded: number, counts: { number }): any
	return {
		name = name,
		boxes = buffer.create(0),
		recorded = recorded,
		dropped = counts[1],
		reads = counts[2],
		walkers = recorded + counts[1],
		skipped = counts[3],
		failed = counts[4],
	}
end

local function source(name: string, counts: { number }, recorded: any?): any
	return {
		name = name,
		boxes = counts[1],
		settled = counts[2],
		inside = counts[3],
		unsound = 0,
		terrain = counts[4],
		recording = recorded,
	}
end

-- Figures that pass, built fresh: P7's boxes and two loads', each clone's answers the main thread's own
local function passing(): any
	return {
		workers = WORKERS,
		wait = WAIT,
		sources = {
			source("P7", { 2000, 1200, 780, 20 }),
			source("S3", { 3000, 2250, 700, 0 }, recording("S3", 3000, { 12, 45000, 3, 0 })),
			source("Spread150", { 1500, 500, 1000, 4 }, recording("Spread150", 1500, { 0, 22000, 0, 1 })),
		},
		expected = answers(ANSWERS),
		answers = { answers(ANSWERS), answers(ANSWERS) },
		failures = {},
	}
end

local FAULTS: { Fault } = {
	{
		label = "an unsound box",
		plant = function (figures: any)
			local spread: any = figures.sources[3]
			spread.unsound = 2
			spread.first = UNSOUND_AT
		end,
		needles = { "Spread150", "2 of 1500 boxes unsound", UNSOUND_AT },
	},
	{
		label = "a clone answering two boxes the other way round, its count of overlaps alike",
		plant = function (figures: any)
			figures.answers[2] = answers({ 1, 1, 0, 1, 0, 0 })
		end,
		needles = {
			"clone 2",
			"2 of 6 boxes answered otherwise",
			"box 2: ours 0000000000000000, theirs 3ff0000000000000",
		},
	},
	{
		label = "a clone's error",
		plant = function (figures: any)
			figures.answers[1] = nil
			figures.failures[1] = "Workspace:GetPartBoundsInBox is not safe to call in parallel"
		end,
		needles = { "clone 1", "failed: Workspace:GetPartBoundsInBox is not safe to call in parallel" },
	},
	{
		label = "a silent clone",
		plant = function (figures: any)
			figures.answers[2] = nil
		end,
		needles = { "no answer from clone 2 within 30 s" },
	},
	{
		label = "a load that recorded no boxes",
		plant = function (figures: any)
			table.insert(figures.sources, source("S4", { 0, 0, 0, 0 }, recording("S4", 0, { 0, 0, 0, 0 })))
		end,
		needles = { "S4: no boxes" },
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared

	-- The dev shared table stands in empty, since the judge reads nothing of it
	local results: { [any]: any } = { [shared.Dev.Config] = {} }
	local Bounds: any =
		Kit.loader(dataModel, { [server.Parallel.Bounds] = BOUNDS }, results, loaded.require)(server.Parallel.Bounds)

	-- 1) Figures that pass give each line as the probe prints it and no problem
	local lines: { string }, problems: { string } = Bounds.judge(passing())
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

	-- 2) Each fault gives one problem holding its source or clone and what was wrong
	for _, fault: Fault in FAULTS do
		local figures: any = passing()
		fault.plant(figures)

		local _, found: { string } = Bounds.judge(figures)
		if #found ~= 1 then
			return false, `{fault.label} gave {#found} problems: {table.concat(found, SEPARATOR)}`
		end

		for _, needle: string in fault.needles do
			if string.find(found[1], needle, 1, true) == nil then
				return false, `{fault.label} gave "{found[1]}", which does not name "{needle}"`
			end
		end
	end

	-- 3) A stop before the clones were asked is a problem, and every clone is named silent
	local short: any = passing()
	short.stopped = "it threw: a planted throw"
	short.expected = nil
	short.answers = {}

	local shortLines: { string }, stopped: { string } = Bounds.judge(short)
	local said: string = "stopped short: it threw: a planted throw | no answer from clones 1, 2 within 30 s"
	if table.concat(stopped, SEPARATOR) ~= said then
		return false, `A stop before the clones answered gave {table.concat(stopped, SEPARATOR)}`
	end

	if shortLines[#shortLines] ~= "ParallelBounds clone 2: no answer within 30 s" then
		return false, `A stop before the clones answered ended its lines with "{shortLines[#shortLines]}"`
	end

	return true, nil
end
