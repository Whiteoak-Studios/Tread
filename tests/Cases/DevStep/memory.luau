--[[
    Verdict memory's lever is set only by its name, never by a session's
    flip or another run, a name no live lever has is refused, and the memory
    run flips it alone off then on, putting it back after each half
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local NAME: string = "verdictMemory"
local UNKNOWN: string = "noSuchLever"
local BOOT: string = "relayClocks" -- A boot lever's name, which no flip can set
local LOAD: string = "Rooms150"
local TITLE: string = "Step benchmark verdict memory run session 3, "

-- Each live lever's state as the dev server starts them, verdict memory off, in name order, and with it alone on
local STARTED: string = table.concat({
	"antiEspWhole true,antiEspWorkers false,bands true,crowdCap true,farUnderLoad true,lazyDecode true",
	"nearRate60 false,npcBudget true,ownerChecks true,relayBudget true,stageSplit false,verdictMemory false",
}, ",")
local REMEMBERING: string = table.concat({
	"antiEspWhole true,antiEspWorkers false,bands true,crowdCap true,farUnderLoad true,lazyDecode true",
	"nearRate60 false,npcBudget true,ownerChecks true,relayBudget true,stageSplit false,verdictMemory true",
}, ",")

-- Each live lever's state now, by name, in name order
local function statesOf(Levers: any): string
	local found: { string } = {}
	for _, lever: any in Levers.list do
		if lever.live then
			table.insert(found, `{lever.name} {lever.get()}`)
		end
	end

	table.sort(found)

	return table.concat(found, ",")
end

-- Each state a flip found, by name, in name order
local function foundOf(states: { [string]: boolean }): string
	local found: { string } = {}
	for name: string, state: boolean in states do
		table.insert(found, `{name} {state}`)
	end

	table.sort(found)

	return table.concat(found, ",")
end

-- Each half drives, the after half showing a test answered from memory a tick, so the run passes
local function answer(_: string, half: string?): (boolean, string, { [string]: number }?)
	local kept: number = 0
	if half == "after" then
		kept = 1
	end

	return true, "drove and cleaned up", { skipped = 1, antiEspKept = kept, antiEspBoxRays = 0 }
end

return function (): (boolean, string | nil)
	local mounted: Step.Mounted = Step.load(answer)
	local Levers: any = mounted.Levers
	local AntiEsp: any = mounted.AntiEsp

	-- 1) The lever: session 2's, live, alone, read and set through verdict memory's own seam
	local lever: any = nil
	for _, listed: any in Levers.list do
		if listed.name == NAME then
			lever = listed
		end
	end

	if lever == nil then
		return false, `No lever is named {NAME}`
	elseif lever.session ~= 2 or lever.live ~= true or lever.alone ~= true then
		return false, `{NAME} is session {lever.session}, live {lever.live} and alone {lever.alone}`
	elseif lever.get ~= AntiEsp.memoryOn or lever.set ~= AntiEsp.useMemory then
		return false, `{NAME} is not read and set through AntiEsp.memoryOn and AntiEsp.useMemory`
	elseif statesOf(Levers) ~= STARTED then
		return false, `The live levers started as {statesOf(Levers)}`
	end

	-- 2) Session 2's flip on, with no name, sets its other three and leaves verdict memory as it was
	local states: { [string]: boolean }, refused: { string } = Levers.flip(2, true)
	if states[NAME] ~= nil or AntiEsp.memoryOn() then
		return false, `Session 2's flip on set {NAME}, which it leaves alone`
	elseif foundOf(states) ~= "antiEspWorkers false,bands true,crowdCap true" or #refused > 0 then
		return false, `Session 2's flip on found {foundOf(states)} and refused {table.concat(refused, ", ")}`
	end

	Levers.restore(states)

	-- 3) By its name: verdict memory alone on, every other lever as it was, and restore puts it back off
	states, refused = Levers.flip(2, true, NAME)
	local now: string = statesOf(Levers)
	if foundOf(states) ~= `{NAME} false` or #refused > 0 then
		return false, `The flip by name found {foundOf(states)} and refused {table.concat(refused, ", ")}`
	elseif now ~= REMEMBERING then
		return false, `After the flip by name the live levers stood {now}`
	elseif not string.find(Levers.line(), `{NAME} (session 2, live) on`, 1, true) then
		return false, `With verdict memory on the line read:\n{Levers.line()}`
	end

	local unrestored: { string } = Levers.restore(states)
	if statesOf(Levers) ~= STARTED or #unrestored > 0 then
		return false, `After restore the live levers stood {statesOf(Levers)}`
	end

	-- 4) A name sets that live lever whatever the session given, and no other
	states = Levers.flip(2, false, "lazyDecode")
	if foundOf(states) ~= "lazyDecode true" or mounted.Commands.lazyOn() ~= false then
		return false, `A flip of lazyDecode by name with session 2 found {foundOf(states)}`
	end

	Levers.restore(states)

	-- 5) A name no live lever has, a boot lever's among them, sets nothing and gives the refusal line
	for _, name: string in { UNKNOWN, BOOT } do
		states, refused = Levers.flip(2, true, name)
		if next(states) ~= nil or statesOf(Levers) ~= STARTED then
			return false, `A flip by the name {name} set {foundOf(states)}`
		elseif table.concat(refused, ",") ~= `no live lever is named {name}` then
			return false, `A flip by the name {name} refused {table.concat(refused, ",")}`
		end
	end

	-- 6) The memory run: its one load before then after, verdict memory alone off then on, the rest as the server
	-- had them in both halves, verdict memory put back off after, and the header naming it in each half
	local passed: boolean, reason: string? = mounted.BenchStep("memory")
	if not passed then
		return false, `A memory run whose halves showed memory failed: {reason}`
	elseif #mounted.asked ~= 2 then
		return false, `The memory run asked for {#mounted.asked} halves, not 2`
	end

	for index: number, half: string in { "before", "after" } do
		local asked: Step.Asked = mounted.asked[index]
		local memory: boolean = half == "after"
		if asked.scenario ~= LOAD or asked.half ~= half or asked.workers ~= true then
			return false, `The memory run's half {index} was {asked.scenario}/{asked.half}, workers {asked.workers}`
		elseif asked.memory ~= memory then
			return false, `The memory run's {half} half ran with verdict memory {asked.memory}`
		elseif asked.bands ~= 3 or not asked.crowd or asked.antiEsp or not asked.lazy or not asked.checks then
			return false, `The memory run's {half} half ran with the session's other levers set`
		elseif not asked.whole or asked.relayBudget == nil or asked.underLoad == nil or asked.split then
			return false, `The memory run's {half} half ran with step 3's levers otherwise than the server has them`
		end
	end

	local header: string = mounted.events[1]
	local at: number? = string.find(header, "; after: ", 1, true)
	local before: string = string.sub(header, 1, at or 0)
	local after: string = string.sub(header, at or #header + 1)
	if statesOf(Levers) ~= STARTED then
		return false, `After the memory run the live levers stood {statesOf(Levers)}`
	elseif string.sub(header, 1, #TITLE) ~= TITLE then
		return false, `The memory run's header opened:\n{header}`
	elseif not string.find(before, `; before: `, 1, true) then
		return false, `The memory run's header named no before half:\n{header}`
	elseif not string.find(before, `{NAME} (session 2, live) off, `, 1, true) then
		return false, `The memory run's header named no before half with memory off:\n{header}`
	elseif not string.find(after, `{NAME} (session 2, live) on, `, 1, true) then
		return false, `The memory run's header named no after half with memory on:\n{header}`
	end

	-- Then each half as asked, then the load's table, and nothing else
	local order: string = table.concat(mounted.events, "\n", 2, 3)
	local closing: string? = mounted.events[4]
	if order ~= `half {LOAD}/before\nhalf {LOAD}/after` or #mounted.events ~= 4 then
		return false, `The memory run went:\n{table.concat(mounted.events, "\n")}`
	elseif not closing or string.find(closing, `{LOAD} table, figure: before after change percent`, 1, true) ~= 1 then
		return false, `The memory run closed on:\n{closing}`
	end

	-- 7) Started with verdict memory on, both halves still run off then on, and it is put back on
	local opposite: Step.Mounted = Step.load(answer)
	opposite.AntiEsp.useMemory(true)
	opposite.BenchStep("memory")
	if not opposite.AntiEsp.memoryOn() then
		return false, "A memory run started with verdict memory on left it off"
	elseif opposite.asked[1].memory or not opposite.asked[2].memory then
		return false, "A memory run started with verdict memory on ran its halves otherwise"
	end

	-- 8) The step benchmark and its noise run leave verdict memory off in every half they ask for
	for _, run: string in { "step benchmark", "noise run" } do
		local other: Step.Mounted = Step.load(answer)
		if run == "noise run" then
			other.BenchStepNoise()
		else
			other.BenchStep()
		end

		if #other.asked ~= 6 then
			return false, `The {run} asked for {#other.asked} halves, not 6`
		end

		for _, asked: Step.Asked in other.asked do
			if asked.memory ~= false then
				return false, `The {run}'s {asked.scenario}/{asked.half} half ran with verdict memory {asked.memory}`
			end
		end
	end

	return true, nil
end
