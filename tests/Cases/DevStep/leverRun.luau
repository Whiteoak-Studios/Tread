--[[
    The levers run flips each of session 2's levers alone on its own load,
    by its name, with the others and the frame caps held off for the run,
    each table titled by its load and lever, and puts back what it found
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local TITLE: string = "Step benchmark levers run session 3, "
local NO_CAPS: string = "false nil nil nil"
local CAPS: string = "true 0.001 0.005 20/0.5"
local HELD: string = "held for the run, each load's own lever off before and on after: "

-- The levers line as the run holds them: session 2's three off, the split as the server starts it, the caps off
local LEVERS: string = table.concat({
	"bands (session 2, live) off",
	"crowdCap (session 2, live) off",
	"antiEspWorkers (session 2, live) off",
	"verdictMemory (session 2, live) off",
	"stageSplit (session 3, live) off",
	"antiEspWhole (session 3, live) off",
	"npcBudget (session 3, live) off",
	"relayBudget (session 3, live) off",
	"farUnderLoad (session 3, live) off",
}, ", ")

-- What the run printed and asked for, in order: before then after for the crowd cap and the bands, after first for
-- anti-ESP's workers
local ORDER: { string } = {
	"header",
	"half S4/before",
	"half S4/after",
	"S4 crowdCap table",
	"half S4/after",
	"half S4/before",
	"S4 antiEspWorkers table",
	"half Spread300/before",
	"half Spread300/after",
	"Spread300 bands table",
}

-- Which of session 2's levers each half asked for ran on, as bands, crowd cap and anti-ESP's workers, in order
local ON: { string } = {
	"false false false",
	"false true false",
	"false false true",
	"false false false",
	"false false false",
	"true false false",
}

-- Each half drives and gives its figures
local function answer(_: string, _: string?): (boolean, string, { [string]: number }?)
	return true, "drove and cleaned up", { skipped = 1 }
end

-- Each event as the order names it: a half as asked, a table by its title, and the first line as the header
local function eventsOf(events: { string }): { string }
	local named: { string } = {}
	for index: number, event: string in events do
		local title: string? = string.match(event, "^(.-) table, figure: ")
		if index == 1 then
			table.insert(named, "header")
		elseif title then
			table.insert(named, `{title} table`)
		else
			table.insert(named, event)
		end
	end

	return named
end

-- Session 2's levers a half asked for, as ON gives them: the dev place's three bands, a crowd cap, anti-ESP's workers
local function onOf(asked: Step.Asked): string
	return `{asked.bands == 3} {asked.crowd} {asked.antiEsp}`
end

return function (): (boolean, string | nil)
	-- 1) Through its scenario: each pair in its order, its lever alone set, the other two and the caps held off, the
	-- split, verdict memory and step 1's as the server started them
	local mounted: Step.Mounted = Step.load(answer)
	local passed: boolean, reason: string? = mounted.BenchStepLevers()
	local events: string = table.concat(eventsOf(mounted.events), ",")
	if not passed then
		return false, `A levers run whose halves all drove failed: {reason}`
	elseif events ~= table.concat(ORDER, ",") then
		return false, `The levers run went {events}`
	elseif #mounted.asked ~= #ON then
		return false, `The levers run asked for {#mounted.asked} halves, not {#ON}`
	end

	for index: number, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		if onOf(asked) ~= ON[index] then
			return false, `Half {index}, {name}, ran with session 2's levers {onOf(asked)}, not {ON[index]}`
		elseif Step.asked(asked) ~= NO_CAPS then
			return false, `Half {index}, {name}, ran with the caps {Step.asked(asked)}`
		elseif asked.split or asked.memory or not asked.lazy or not asked.checks or asked.workers ~= true then
			return false, `Half {index}, {name}, ran with the split, verdict memory or step 1's otherwise`
		end
	end

	-- 2) The header: its title, and the levers once as held, no split note
	local header: string = mounted.events[1]
	if string.sub(header, 1, #TITLE) ~= TITLE or string.find(header, "with stageSplit on", 1, true) then
		return false, `The levers run's header read:\n{header}`
	elseif not string.find(header, HELD, 1, true) then
		return false, `The levers run's header named no hold:\n{header}`
	elseif string.sub(header, -#LEVERS) ~= LEVERS or string.find(header, "; before: ", 1, true) then
		return false, `The levers run's header did not end on the held levers:\n{header}`
	end

	-- 3) Everything put back as the server started it once the run ends
	local bands: number = #mounted.Relay.bands()
	if Step.caps(mounted) ~= CAPS or bands ~= 3 or mounted.Relay.crowd() == nil or mounted.AntiEsp.workersOn() then
		return false, `The levers run left the caps {Step.caps(mounted)} and session 2's levers otherwise`
	end

	-- 4) Started the other way, anti-ESP's workers on and the caps off, each half still runs as held, and each lever is
	-- put back as found
	local opposite: Step.Mounted = Step.load(answer)
	opposite.AntiEsp.useWorkers(true)
	Step.capsOff(opposite)
	opposite.BenchStep("levers")

	for index: number, asked: Step.Asked in opposite.asked do
		if onOf(asked) ~= ON[index] or Step.asked(asked) ~= NO_CAPS then
			return false, `Started the other way, half {index} ran with {onOf(asked)} and the caps {Step.asked(asked)}`
		end
	end

	if not opposite.AntiEsp.workersOn() or Step.caps(opposite) ~= NO_CAPS or #opposite.Relay.bands() ~= 3 then
		return false, "Started the other way, the levers run did not put each lever back as it found it"
	end

	return true, nil
end
