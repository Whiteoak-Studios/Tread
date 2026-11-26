--[[
    The step benchmark prints its header, runs each load's halves in the
    design's order with step 3's caps set for each, prints that load's
    table, a failed half missing while the rest still run, and the noise
    run takes the same loads twice with them on, set once and put back
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

-- Step 1's live levers as they stand, on as the dev server starts them, and off in a noise run that started so
local STEP_1: string = "lazyDecode (session 1, live) on, ownerChecks (session 1, live) on"
local STEP_1_OFF: string = "lazyDecode (session 1, live) off, ownerChecks (session 1, live) off"

-- Step 2's as every half's header part names them, as the dev server starts them, verdict memory off
local STEP_2: string = table.concat({
	"bands (session 2, live) on",
	"crowdCap (session 2, live) on",
	"antiEspWorkers (session 2, live) off",
	"verdictMemory (session 2, live) off",
}, ", ")

-- Step 3's: the split left off by every run but its own, and the four caps off before and on after
local SPLIT_OFF: string = "stageSplit (session 3, live) off"
local CAPS_OFF: string = table.concat({
	"antiEspWhole (session 3, live) off",
	"npcBudget (session 3, live) off",
	"relayBudget (session 3, live) off",
	"farUnderLoad (session 3, live) off",
}, ", ")
local CAPS_ON: string = table.concat({
	"antiEspWhole (session 3, live) on",
	"npcBudget (session 3, live) on",
	"relayBudget (session 3, live) on",
	"farUnderLoad (session 3, live) on",
}, ", ")

-- The levers each half's header part names: session 3's caps off before and on after, and on in both halves of a
-- noise run, beside step 1's as they stood
local BEFORE: string = `{STEP_1}, {BOOT}, {STEP_2}, {SPLIT_OFF}, {CAPS_OFF}`
local AFTER: string = `{STEP_1}, {BOOT}, {STEP_2}, {SPLIT_OFF}, {CAPS_ON}`
local NOISE_LEVERS: string = `{STEP_1_OFF}, {BOOT}, {STEP_2}, {SPLIT_OFF}, {CAPS_ON}`

-- What the header says of step 3's build in every run, between its workers and its levers
local NOTES: string = table.concat({
	"the worker clock's unpack section holds each worker's read of its own hand-in",
	"with relayBudget on, a viewer's turn after a run that left it can carry that run's footsteps, which raises the "
		.. "bytes rows and leaves the records rows alone",
}, "; ")

-- The header's workers with the stand-in's anti-ESP pool of 2, and with none
local POOLED: string = "4 relay workers started, 2 anti-ESP workers made"
local UNPOOLED: string =
	"4 relay workers started, no anti-ESP workers made, so every ray is cast in process however antiEspWorkers reads"

-- The four caps as a half asks for them, worked from the stand-in server's settings, and with each off
local CAPS: string = "true 0.001 0.005 20/0.5"
local NO_CAPS: string = "false nil nil nil"

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

	-- 1) The order, each half on the relay's workers with the step's timing, step 3's caps off before and on after,
	-- Spread150's after half first, and step 1's, step 2's and the split as the server has them in every half
	local passed: boolean, reason: string? = mounted.BenchStep()
	local events: { string } = eventsOf(mounted.events)
	if not passed then
		return false, `A run whose halves all drove failed: {reason}`
	elseif table.concat(events, ",") ~= table.concat(ORDER, ",") then
		return false, `The run went {table.concat(events, ",")}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		local after: boolean = asked.half == "after"
		if asked.workers ~= true or asked.timing ~= timing then
			return false, `{name} was asked for with workers {asked.workers} and its own timing`
		elseif Step.asked(asked) ~= (after and CAPS or NO_CAPS) then
			return false, `{name} ran with the caps {Step.asked(asked)}`
		elseif asked.bands ~= 3 or not asked.crowd or asked.antiEsp or asked.memory or asked.split then
			return false, `{name} ran with {asked.bands} bands, a crowd cap {asked.crowd}, anti-ESP's {asked.antiEsp}`
		elseif asked.lazy ~= true or asked.checks ~= true then
			return false, `{name} ran with lazy decode {asked.lazy} and owner checks {asked.checks}`
		end
	end

	if Commands.lazyOn() ~= true then
		return false, "The run left lazy decode off"
	elseif Characters.checksOn() ~= true then
		return false, "The run left owner checks off"
	elseif Step.caps(mounted) ~= CAPS then
		return false, `The run left the caps {Step.caps(mounted)}`
	end

	-- 2) The header: the session, the date, the place's version and job, the players, the relay workers started and
	-- the anti-ESP workers made, the build's notes and each half's levers
	local header: string = mounted.events[1]
	local title: string = "Step benchmark session 3, "
	local date: string? = string.match(string.sub(header, #title + 1), DATE)
	local server: string = `place version 412, job job-1, 0 real players in, {POOLED}`
	local rest: string = `{server}; {NOTES}; before: {BEFORE}; after: {AFTER}`

	if string.sub(header, 1, #title) ~= title or date == nil then
		return false, `The header opened:\n{header}`
	elseif string.sub(header, #title + #date + #" UTC, " + 1) ~= rest then
		return false, `The header read:\n{header}\nnot, after its date:\n{rest}`
	end

	-- And a server that made no anti-ESP workers says so, and that every ray is cast in process
	local unpooled: Step.Mounted = Step.load(answers(nil, nil))
	unpooled.settings.antiEsp = { whole = true }
	unpooled.BenchStep()
	if not string.find(unpooled.events[1], `, 0 real players in, {UNPOOLED}; {NOTES}; before: `, 1, true) then
		return false, `With no anti-ESP workers, the header read:\n{unpooled.events[1]}`
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

	-- 5) The noise run: the same loads, first then second, step 3's caps on in every half and named so, step 1's
	-- left as they stood, off here, and the caps put back as the dev server starts them once it ends
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
		if asked.lazy ~= false or asked.checks ~= false or Step.asked(asked) ~= CAPS or asked.split then
			return false, `The noise run's {asked.scenario}/{asked.half} ran without step 3's caps on alone`
		elseif asked.bands ~= 3 or not asked.crowd or asked.antiEsp then
			return false, `The noise run's {asked.scenario}/{asked.half} ran with step 2's levers otherwise`
		end
	end

	if Step.caps(noise) ~= CAPS or noise.Commands.lazyOn() or noise.Characters.checksOn() then
		return false, "The noise run left a lever other than as it found it"
	end

	local opening: string = noise.events[1]
	local split: string = "Step benchmark noise run session 3, "
	local halves: string = `; {NOTES}; first: {NOISE_LEVERS}; second: {NOISE_LEVERS}`
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

	-- 6) Started with the caps off, the noise run still runs both halves with them on and puts each back off, the far
	-- rate cleared before the budget it needs
	local opposite: Step.Mounted = Step.load(answers(nil, nil))
	Step.capsOff(opposite)
	local opposed: boolean, opposedWhy: string? = opposite.BenchStepNoise()

	for _, asked: Step.Asked in opposite.asked do
		if Step.asked(asked) ~= CAPS then
			local caps: string = Step.asked(asked)
			return false, `Started with the caps off, the noise run's {asked.scenario}/{asked.half} ran with {caps}`
		end
	end

	if not opposed then
		return false, `Started with the caps off, the noise run failed: {opposedWhy}`
	elseif Step.caps(opposite) ~= NO_CAPS then
		return false, `Started with the caps off, the noise run left them {Step.caps(opposite)}`
	end

	-- 7) An NPC budget the server's check refuses: the noise run names the refusal and fails, and both halves still
	-- run with the rest of step 3's caps on and keep their figures
	local refusing: Step.Mounted = Step.load(answers(nil, nil))
	refusing.Npcs.setBudget(nil)
	refusing.settings.npcs.budget = -1

	local refusedRun: boolean, refusedWhy: string? = refusing.BenchStepNoise()
	local refusal: string = refusedWhy or ""
	if refusedRun then
		return false, "A noise run whose NPC budget was refused passed"
	elseif not string.find(refusal, "Step benchmark noise run's levers refused: npcBudget refused on: ", 1, true) then
		return false, `The refused noise run's reason read:\n{refusal}`
	elseif not string.find(tableOf(refusing.events, "Spread150"), ": 300 400 +100 ", 1, true) then
		return false, `The refused noise run's Spread150 table read:\n{tableOf(refusing.events, "Spread150")}`
	elseif #refusing.asked ~= 6 then
		return false, `The refused noise run asked for {#refusing.asked} halves, not 6`
	end

	for _, asked: Step.Asked in refusing.asked do
		if Step.asked(asked) ~= "true nil 0.005 20/0.5" then
			return false, `The refused noise run's {asked.scenario}/{asked.half} ran with the caps {Step.asked(asked)}`
		end
	end

	return true, nil
end
