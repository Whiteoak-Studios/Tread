--[[
    The split run takes the step benchmark's loads in their halves' order
    with the split by stage flipped alone, the frame caps as the server has
    them, its header noting what the split moves, and puts the split back
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local TITLE: string = "Step benchmark split run session 3, "
local NAME: string = "stageSplit"
local CAPS: string = "true 0.001 0.005 20/0.5" -- The caps as the stand-in server starts them, which both halves keep

-- What the header says of the split, beside the build's notes every session 3 run gives
local NOTE: string = "; with stageSplit on, the frame holding a tick holds frame 1 alone, the relay's dispatch moves to "
	.. "the Heartbeat after and the bots' stage to the one after that; before: "

-- What the run printed and asked for, in order, as the step benchmark's order runs them
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

return function (): (boolean, string | nil)
	-- 1) Through its scenario: the loads in their order, the split off before and on after alone, the caps and every
	-- other lever as the server started them in every half, and the split put back off
	local mounted: Step.Mounted = Step.load(answer)
	local passed: boolean, reason: string? = mounted.BenchStepSplit()
	local events: string = table.concat(eventsOf(mounted.events), ",")
	if not passed then
		return false, `A split run whose halves all drove failed: {reason}`
	elseif events ~= table.concat(ORDER, ",") then
		return false, `The split run went {events}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		if asked.split ~= (asked.half == "after") then
			return false, `{name} ran with the split {asked.split}`
		elseif Step.asked(asked) ~= CAPS then
			return false, `{name} ran with the caps {Step.asked(asked)}`
		elseif asked.bands ~= 3 or not asked.crowd or asked.antiEsp or asked.memory or not asked.lazy then
			return false, `{name} ran with a lever of session 1 or 2 otherwise than the server has it`
		end
	end

	if mounted.Tick.splitOn() or Step.caps(mounted) ~= CAPS then
		return false, `The split run left the split {mounted.Tick.splitOn()} and the caps {Step.caps(mounted)}`
	end

	-- 2) The header: its title, the split's note, and the split named off before and on after
	local header: string = mounted.events[1]
	local at: number? = string.find(header, "; after: ", 1, true)
	local before: string = string.sub(header, 1, at or 0)
	local after: string = string.sub(header, at or #header + 1)
	if string.sub(header, 1, #TITLE) ~= TITLE then
		return false, `The split run's header opened:\n{header}`
	elseif not string.find(header, NOTE, 1, true) then
		return false, `The split run's header gave no note of what the split moves:\n{header}`
	elseif not string.find(before, `{NAME} (session 3, live) off, `, 1, true) then
		return false, `The split run's header named no before half with the split off:\n{header}`
	elseif not string.find(after, `{NAME} (session 3, live) on, `, 1, true) then
		return false, `The split run's header named no after half with the split on:\n{header}`
	end

	-- 3) Started with the split on, each half still runs off then on, and it is put back on
	local opposite: Step.Mounted = Step.load(answer)
	opposite.Tick.useSplit(true)
	opposite.BenchStep("split")
	if not opposite.Tick.splitOn() then
		return false, "A split run started with the split on left it off"
	end

	for _, asked: Step.Asked in opposite.asked do
		if asked.split ~= (asked.half == "after") then
			return false, `Started with the split on, {asked.scenario}/{asked.half} ran with it {asked.split}`
		end
	end

	-- 4) Only the split run notes it: the step benchmark's header does not
	local plain: Step.Mounted = Step.load(answer)
	plain.BenchStep()
	if string.find(plain.events[1], "with stageSplit on", 1, true) then
		return false, `The step benchmark's header noted the split:\n{plain.events[1]}`
	end

	return true, nil
end
