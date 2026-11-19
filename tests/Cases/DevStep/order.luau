--[[
    The step benchmark prints its header, runs each load's halves in the
    design's order with the levers set for each, then prints that load's
    table, a failed half missing from it while the rest still run, and the
    noise run takes the same loads twice over with no lever flipped
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local DATE: string = "^(%d%d%d%d%-%d%d%-%d%d) UTC, " -- The header's UTC date, after its title and session

-- The boot levers as the header names them in every half, with the stand-in server's settings
local BOOT: string = table.concat({
	"relayWorkers (session 0, boot) on",
	"relayClocks (session 1, boot) on",
	"outOfView (session 0, boot) on",
	"changes (session 0, boot) on",
}, ", ")

-- The levers each half's header part names: session 1's live levers off before and on after, and off in both of a
-- noise run that started with them off
local BEFORE: string = `lazyDecode (session 1, live) off, ownerChecks (session 1, live) off, {BOOT}`
local AFTER: string = `lazyDecode (session 1, live) on, ownerChecks (session 1, live) on, {BOOT}`

-- Each half's mark in the figures it gives, so a table's columns show whose they hold
local MARKS: { [string]: number } = { before = 100, after = 200, first = 300, second = 400 }

-- What the run printed and asked for, in order: before then after at S4 and Spread300, after first at Spread150
local ORDER: { string } = {
	"header",
	"half S4/before",
	"half S4/after",
	"S4 table",
	"half Spread150/after",
	"half Spread150/before",
	"Spread150 table",
	"half Spread300/before",
	"half Spread300/after",
	"Spread300 table",
}

local NOISE_ORDER: { string } = {
	"header",
	"half S4/first",
	"half S4/second",
	"S4 table",
	"half Spread150/first",
	"half Spread150/second",
	"Spread150 table",
	"half Spread300/first",
	"half Spread300/second",
	"Spread300 table",
}

-- Each event as the order names it: a half as asked, a table by its load, and the first line as the header
local function eventsOf(events: { string }): { string }
	local named: { string } = {}
	for index: number, event: string in events do
		local load: string? = string.match(event, "^(%S+) table, ")
		if index == 1 then
			table.insert(named, "header")
		elseif load then
			table.insert(named, `{load} table`)
		else
			table.insert(named, event)
		end
	end

	return named
end

-- The table event of a load, by its load's name
local function tableOf(events: { string }, load: string): string
	for _, event: string in events do
		if string.find(event, `{load} table, `, 1, true) == 1 then
			return event
		end
	end

	return ""
end

-- Each half drives and gives its mark as the commands skipped, but those the given names fail or throw
local function answers(failing: string?, throwing: string?): Step.Answer
	return function (scenario: string, half: string?): (boolean, string, { [string]: number }?)
		local name: string = `{scenario}/{half}`
		if name == throwing then
			error("a stand-in throw", 0)
		elseif name == failing then
			return false, `Bots {name} seed 1: a stand-in failure`, { skipped = 1 }
		end

		return true, `Bots {name} seed 1: drove and cleaned up`, { skipped = MARKS[half :: string] }
	end
end

return function (): (boolean, string | nil)
	local mounted: Step.Mounted = Step.load(answers(nil, nil))
	local Commands: any = mounted.Commands
	local Characters: any = mounted.Characters
	local timing: any = mounted.Config.step.timing

	-- 1) The order, each half on the relay's workers with the step's timing and both live levers off before and on
	-- after, Spread150's after half first
	local passed: boolean, reason: string? = mounted.BenchStep()
	local events: { string } = eventsOf(mounted.events)
	if not passed then
		return false, `A run whose halves all drove failed: {reason}`
	elseif table.concat(events, ",") ~= table.concat(ORDER, ",") then
		return false, `The run went {table.concat(events, ",")}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		if asked.workers ~= true or asked.timing ~= timing then
			return false, `{name} was asked for with workers {asked.workers} and its own timing`
		elseif asked.lazy ~= (asked.half == "after") then
			return false, `{name} ran with lazy decode {asked.lazy}`
		elseif asked.checks ~= (asked.half == "after") then
			return false, `{name} ran with owner checks {asked.checks}`
		end
	end

	if Commands.lazyOn() ~= true then
		return false, "The run left lazy decode off"
	elseif Characters.checksOn() ~= true then
		return false, "The run left owner checks off"
	end

	-- 2) The header: the session, the date, the place's version and job, the players, workers and each half's levers
	local header: string = mounted.events[1]
	local title: string = "Step benchmark session 1, "
	local date: string? = string.match(string.sub(header, #title + 1), DATE)
	local server: string = "place version 412, job job-1, 0 real players in, 4 relay workers started"
	local rest: string = `{server}; before: {BEFORE}; after: {AFTER}`

	if string.sub(header, 1, #title) ~= title or date == nil then
		return false, `The header opened:\n{header}`
	elseif string.sub(header, #title + #date + #" UTC, " + 1) ~= rest then
		return false, `The header read:\n{header}\nnot, after its date:\n{rest}`
	end

	-- 3) Each table's before column is the before half's, Spread150's too, whose after half ran first
	for _, load: string in { "S4", "Spread150", "Spread300" } do
		local skipped: string = "\ncommands lazy decode skipped: 100 200 +100 +100.0%"
		if not string.find(tableOf(mounted.events, load), skipped, 1, true) then
			return false, `{load}'s table read:\n{tableOf(mounted.events, load)}`
		end
	end

	-- 4) A half that fails and one that throws: each reads missing, the rest still run, and the run fails
	local broken: Step.Mounted = Step.load(answers("Spread150/before", "Spread300/after"))
	local ran: boolean, why: string? = broken.BenchStep()
	local brokenEvents: { string } = eventsOf(broken.events)
	local failedTable: string = tableOf(broken.events, "Spread150")
	local thrownTable: string = tableOf(broken.events, "Spread300")
	local failure: string = why or ""

	if ran then
		return false, "A run with a failed half and a thrown one passed"
	elseif table.concat(brokenEvents, ",") ~= table.concat(ORDER, ",") then
		return false, `With a failed half and a thrown one, the run went {table.concat(brokenEvents, ",")}`
	elseif not string.find(failedTable, "\ncommands lazy decode skipped: missing 200 n/a", 1, true) then
		return false, `Spread150's table with its before half failed read:\n{failedTable}`
	elseif not string.find(thrownTable, "\ncommands lazy decode skipped: 100 missing n/a", 1, true) then
		return false, `Spread300's table with its after half thrown read:\n{thrownTable}`
	elseif not string.find(failure, "Bots Spread300/after: it threw: a stand-in throw", 1, true) then
		return false, `The failed run's reason was {failure}`
	elseif not string.find(failure, "Bots Spread150/before seed 1: a stand-in failure", 1, true) then
		return false, `The failed run's reason was {failure}`
	end

	-- 5) The noise run: the same loads, first then second, both live levers as they stood in every half and named so
	local noise: Step.Mounted = Step.load(answers(nil, nil))
	noise.Commands.useLazy(false)
	noise.Characters.useChecks(false)

	local quiet: boolean = noise.BenchStepNoise()
	local noiseEvents: { string } = eventsOf(noise.events)
	if not quiet then
		return false, "A noise run whose halves all drove failed"
	elseif table.concat(noiseEvents, ",") ~= table.concat(NOISE_ORDER, ",") then
		return false, `The noise run went {table.concat(noiseEvents, ",")}`
	end

	for _, asked: Step.Asked in noise.asked do
		if asked.lazy ~= false or asked.checks ~= false then
			return false, `The noise run's {asked.scenario}/{asked.half} flipped a live lever on`
		end
	end

	local opening: string = noise.events[1]
	local split: string = "Step benchmark noise run session 1, "
	local halves: string = `; first: {BEFORE}; second: {BEFORE}`
	if string.sub(opening, 1, #split) ~= split then
		return false, `The noise run's header read:\n{opening}`
	elseif string.sub(opening, -#halves) ~= halves then
		return false, `The noise run's header read:\n{opening}\nnot, at its end:\n{halves}`
	end

	local spread: string = tableOf(noise.events, "Spread150")
	if not string.find(spread, "figure: first second change", 1, true) then
		return false, `The noise run's Spread150 table read:\n{spread}`
	elseif not string.find(spread, ": 300 400 +100 ", 1, true) then
		return false, `The noise run's Spread150 table read:\n{spread}`
	end

	return true, nil
end
