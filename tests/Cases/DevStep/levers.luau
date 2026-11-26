--[[
    A flip sets only that session's live levers, step 2's and step 3's on
    the real modules, restore puts each back, also when a half throws, a
    setter that refuses is named and fails its half, and the line names all
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

-- Each live lever, in the list's order, with the session that added it
local LIVE: { [string]: number } = {
	lazyDecode = 1,
	ownerChecks = 1,
	bands = 2,
	crowdCap = 2,
	antiEspWorkers = 2,
	verdictMemory = 2,
	stageSplit = 3,
	antiEspWhole = 3,
	npcBudget = 3,
	relayBudget = 3,
	farUnderLoad = 3,
}
local NAMES: string = table.concat({
	"lazyDecode,ownerChecks,relayWorkers,relayClocks,outOfView,changes",
	"bands,crowdCap,antiEspWorkers,verdictMemory",
	"stageSplit,antiEspWhole,npcBudget,relayBudget,farUnderLoad",
}, ",")

-- Every lever as the line names it with the stand-in server's settings, as the dev server starts them
local LINE: string = table.concat({
	"lazyDecode (session 1, live) on",
	"ownerChecks (session 1, live) on",
	"relayWorkers (session 0, boot) on",
	"relayClocks (session 1, boot) on",
	"outOfView (session 0, boot) on",
	"changes (session 0, boot) on",
	"bands (session 2, live) on",
	"crowdCap (session 2, live) on",
	"antiEspWorkers (session 2, live) off",
	"verdictMemory (session 2, live) off",
	"stageSplit (session 3, live) off",
	"antiEspWhole (session 3, live) on",
	"npcBudget (session 3, live) on",
	"relayBudget (session 3, live) on",
	"farUnderLoad (session 3, live) on",
}, ", ")

-- The relay's bands, aim/floor in Hz, and edges, enter/leave in studs: the dev place's, and the before half's
local STARTED: string = "20/15,10/10,5/5 at 350/385,600/660"
local BEFORE: string = "20/15,15/10 at 200/220"

-- Each lever the stand-in run's halves flip, as it found it at the start, by name and state, in name order
local FOUND: string = "antiEspWorkers false,bands true,crowdCap true"
local CAPS_FOUND: string = "antiEspWhole true,farUnderLoad true,npcBudget true,relayBudget true"

-- The frame caps as the stand-in server's settings start them, and with each off
local CAPS: string = "true 0.001 0.005 20/0.5"
local NO_CAPS: string = "false nil nil nil"

-- The relay's bands and edges in one line
local function bandsOf(Relay: any): string
	local bands: { any }, edges: { any } = Relay.bands()
	local named: { string } = {}
	for _, band: any in bands do
		table.insert(named, `{band.aim}/{band.floor}`)
	end

	local between: { string } = {}
	for _, edge: any in edges do
		table.insert(between, `{edge.enter}/{edge.leave}`)
	end

	return `{table.concat(named, ",")} at {table.concat(between, ",")}`
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

-- A lever that keeps each state it is set to, in a list of its own, or refuses every set when refusing
local function kept(name: string, session: number, live: boolean, sets: { string }, refusing: boolean?): any
	local on: boolean = true

	return {
		name = name,
		session = session,
		live = live,
		get = function (): boolean
			return on
		end,
		set = function (state: boolean)
			if refusing then
				error("a stand-in refusal", 0)
			end

			on = state
			table.insert(sets, `{name} {state}`)
		end,
	}
end

-- Whether step 2's levers stand as given: the relay's bands, whether it holds a crowd cap, and anti-ESP's switch
local function standing(mounted: Step.Mounted, bands: string, crowd: boolean, antiEsp: boolean): string?
	local now: string = bandsOf(mounted.Relay)
	if now ~= bands then
		return `the relay's bands are {now}, not {bands}`
	elseif (mounted.Relay.crowd() ~= nil) ~= crowd then
		return `the relay's crowd cap is {mounted.Relay.crowd()}, not {crowd and "set" or "none"}`
	elseif mounted.AntiEsp.workersOn() ~= antiEsp then
		return `anti-ESP's workers are {mounted.AntiEsp.workersOn()}, not {antiEsp}`
	end

	return nil
end

return function (): (boolean, string | nil)
	-- Each half throws, so every flip must be put back by the half's own restore
	local mounted: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		error("a stand-in throw", 0)
	end)

	local Levers: any = mounted.Levers
	local Commands: any = mounted.Commands
	local Characters: any = mounted.Characters

	-- 1) The list: step 1's, step 2's and step 3's live levers each with its seam, the rest boot levers, and the line
	local names: { string } = {}
	for _, lever: any in Levers.list do
		table.insert(names, lever.name)

		local session: number? = LIVE[lever.name]
		if lever.live ~= (session ~= nil) or (lever.set ~= nil) ~= (session ~= nil) then
			return false, `{lever.name} is listed live {lever.live} with a setter {lever.set ~= nil}`
		elseif session and lever.session ~= session then
			return false, `{lever.name} is listed for session {lever.session}, not session {session}`
		end
	end

	if table.concat(names, ",") ~= NAMES then
		return false, `The levers are {table.concat(names, ",")}`
	elseif Levers.line() ~= LINE then
		return false, `The levers' line read:\n{Levers.line()}\nnot:\n{LINE}`
	end

	-- 2) A flip of session 2 off puts the relay on the before half's bands with no crowd cap and anti-ESP in process,
	-- leaving step 1's and step 3's as they are, and restore puts back what it found
	local states: { [string]: boolean }, refused: { string } = Levers.flip(2, false)
	local problem: string? = standing(mounted, BEFORE, false, false)
	if problem then
		return false, `After session 2's flip off, {problem}`
	elseif #refused > 0 then
		return false, `Session 2's flip off refused: {table.concat(refused, ", ")}`
	elseif Commands.lazyOn() ~= true or Characters.checksOn() ~= true or Step.caps(mounted) ~= CAPS then
		return false, "Session 2's flip off set a lever of session 1 or 3"
	elseif foundOf(states) ~= FOUND then
		return false, `Session 2's flip off found {foundOf(states)}`
	end

	local unrestored: { string } = Levers.restore(states)
	problem = standing(mounted, STARTED, true, false)
	if problem then
		return false, `After session 2's restore, {problem}`
	elseif #unrestored > 0 then
		return false, `Session 2's restore refused: {table.concat(unrestored, ", ")}`
	end

	-- And on: the dev place's bands and crowd cap, and anti-ESP packing for its workers, until restore
	states = Levers.flip(2, true)
	problem = standing(mounted, STARTED, true, true)
	if problem then
		return false, `After session 2's flip on, {problem}`
	elseif foundOf(states) ~= FOUND then
		return false, `Session 2's flip on found {foundOf(states)}`
	end

	Levers.restore(states)
	problem = standing(mounted, STARTED, true, false)
	if problem then
		return false, `After session 2's flip on was restored, {problem}`
	end

	-- A flip of session 3 off clears its four caps and finds each on, leaving the split, which it leaves alone
	states, refused = Levers.flip(3, false)
	if Step.caps(mounted) ~= NO_CAPS or #refused > 0 then
		return false, `Session 3's flip off left the caps {Step.caps(mounted)}, refusing {table.concat(refused, ", ")}`
	elseif foundOf(states) ~= CAPS_FOUND then
		return false, `Session 3's flip off found {foundOf(states)}`
	end

	Levers.restore(states)
	if Step.caps(mounted) ~= CAPS then
		return false, `Session 3's restore left the caps {Step.caps(mounted)}`
	end

	-- 3) Over a list of its own, a flip of session 1 never sets a boot lever of session 1 or a live one of session 2,
	-- and a setter that refuses is named with the state it refused, at the flip and at the restore
	local real: { any } = Levers.list
	local sets: { string } = {}
	Levers.list = {
		kept("ownLive", 1, true, sets),
		kept("ownBoot", 1, false, sets),
		kept("otherLive", 2, true, sets),
		kept("refusing", 1, true, sets, true),
	}

	local own: { [string]: boolean }, ownRefused: { string } = Levers.flip(1, false)
	local ownUnrestored: { string } = Levers.restore(own)
	Levers.list = real

	if table.concat(sets, ",") ~= "ownLive false,ownLive true" then
		return false, `Session 1's flip and restore set {table.concat(sets, ",")}`
	elseif table.concat(ownRefused, ",") ~= "refusing refused off: a stand-in refusal" then
		return false, `The flip's refusals read {table.concat(ownRefused, ",")}`
	elseif table.concat(ownUnrestored, ",") ~= "refusing refused on: a stand-in refusal" then
		return false, `The restore's refusals read {table.concat(ownUnrestored, ",")}`
	end

	-- 4) Every half of the run throws: step 3's caps are as they started afterward, off in each before half and on in
	-- each after half, and step 1's, step 2's and the split stay as the server has them in every half
	local passed: boolean = mounted.BenchStep()
	if passed then
		return false, "A run whose every half threw passed"
	elseif Step.caps(mounted) ~= CAPS then
		return false, `After the halves threw, the caps stood {Step.caps(mounted)}`
	elseif Commands.lazyOn() ~= true or Characters.checksOn() ~= true or mounted.Tick.splitOn() then
		return false, "A run of session 3 left a lever of session 1 off or the split on"
	elseif #mounted.asked ~= 6 then
		return false, `The run asked for {#mounted.asked} halves, not 6`
	end

	problem = standing(mounted, STARTED, true, false)
	if problem then
		return false, `After the halves threw, {problem}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local after: boolean = asked.half == "after"
		local caps: string = Step.asked(asked)
		if caps ~= (after and CAPS or NO_CAPS) then
			return false, `The {asked.scenario}/{asked.half} half ran with the caps {caps}`
		elseif asked.bands ~= 3 or not asked.crowd or asked.antiEsp or asked.split then
			return false, `The {asked.scenario}/{asked.half} half ran with step 2's levers or the split otherwise`
		elseif not asked.lazy or not asked.checks then
			return false, `The {asked.scenario}/{asked.half} half ran with a lever of session 1 off`
		end
	end

	-- 5) And with the caps off and the split on before the run, the halves' throws put each back that way
	Step.capsOff(mounted)
	mounted.Tick.useSplit(true)
	mounted.BenchStep()

	if Step.caps(mounted) ~= NO_CAPS then
		return false, `After a run that started with the caps off, they stood {Step.caps(mounted)}`
	elseif not mounted.Tick.splitOn() then
		return false, "A run that started with the split on left it off"
	end

	-- 6) An NPC budget the server's check refuses: each after half's flip on is refused and named, the half keeps its
	-- figures and the run fails, and the header names the refusals its own flips met
	local refusing: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		return true, "drove and cleaned up", { skipped = 1 }
	end)

	refusing.settings.npcs.budget = -1
	local ran: boolean, why: string? = refusing.BenchStep()
	local reason: string = why or ""

	if ran then
		return false, "A run whose after halves' NPC budget was refused passed"
	elseif not string.find(refusing.events[1], "; after: ", 1, true) then
		return false, `The header read:\n{refusing.events[1]}`
	elseif not string.find(refusing.events[1], ", and refused: npcBudget refused on: ", 1, true) then
		return false, `The header named no refusal:\n{refusing.events[1]}`
	end

	for _, load: string in { "S4", "Spread150", "Spread300" } do
		if not string.find(reason, `Bots {load}/after's levers refused: npcBudget refused on: `, 1, true) then
			return false, `The run's reason named no refusal for {load}'s after half:\n{reason}`
		elseif string.find(reason, `Bots {load}/before's levers refused`, 1, true) then
			return false, `The run's reason named a refusal for {load}'s before half:\n{reason}`
		end
	end

	for _, event: string in refusing.events do
		if
			string.find(event, " table, ", 1, true)
			and not string.find(event, "\ncommands lazy decode skipped: 1 1 ", 1, true)
		then
			return false, `A table left out a half whose lever refused:\n{event}`
		end
	end

	return true, nil
end
