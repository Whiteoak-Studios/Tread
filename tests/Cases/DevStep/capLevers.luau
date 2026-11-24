--[[
    Step 3's levers: the split alone and the four frame caps, each through
    its seam, set on forwards and off backwards so the far rate never stands
    without the relay's budget, each on the value the server's settings hold
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

-- Step 3's levers in the list's order, after verdict memory, and whether each is marked alone
local ORDER: string = "verdictMemory,stageSplit,antiEspWhole,npcBudget,relayBudget,farUnderLoad"
local ALONE: { [string]: boolean } = { stageSplit = true }

-- The caps as the fixture boots them, with each off, and with the settings' values changed below
local CAPS: string = "true 0.001 0.005 20/0.5"
local NO_CAPS: string = "false nil nil nil"
local CHANGED: string = "true 0.0025 0.0075 10/0.25"
local FOUND: string = "antiEspWhole true,farUnderLoad true,npcBudget true,relayBudget true"

-- What the relay says when its budget is cleared under the far rate, and when the far rate is set with no budget
local BUDGET_HELD: string = "Relay.setBudget takes nil only once Relay.setUnderLoad(nil) has turned the far rate "
	.. "under load off"
local NO_BUDGET: string = "Relay.setUnderLoad takes the far rate under load only once Relay.setBudget has set a budget"

-- Each half drives and gives a figure, so its table prints
local function answer(_: string, _: string?): (boolean, string, { [string]: number }?)
	return true, "drove and cleaned up", { skipped = 1 }
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

-- The lever of that name
local function leverOf(Levers: any, name: string): any
	for _, lever: any in Levers.list do
		if lever.name == name then
			return lever
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local mounted: Step.Mounted = Step.load(answer)
	local Levers: any = mounted.Levers
	local Tick: any = mounted.Tick
	local AntiEsp: any = mounted.AntiEsp

	-- 1) The fixture boots the caps on as the dev server does, the split off, and the five levers follow verdict
	-- memory in the design's order, live and of session 3, the split alone and the caps not
	local names: { string } = {}
	local from: boolean = false
	for _, lever: any in Levers.list do
		from = from or lever.name == "verdictMemory"
		if from then
			table.insert(names, lever.name)
		end
	end

	if Step.caps(mounted) ~= CAPS or Tick.splitOn() then
		return false, `The fixture booted the caps {Step.caps(mounted)} with the split {Tick.splitOn()}`
	elseif table.concat(names, ",") ~= ORDER then
		return false, `The list ends {table.concat(names, ",")}`
	end

	for index: number = 2, #names do
		local lever: any = leverOf(Levers, names[index])
		if lever.session ~= 3 or lever.live ~= true or (lever.alone == true) ~= (ALONE[lever.name] == true) then
			return false, `{lever.name} is session {lever.session}, live {lever.live} and alone {lever.alone}`
		end
	end

	local split: any, whole: any = leverOf(Levers, "stageSplit"), leverOf(Levers, "antiEspWhole")
	if split.get ~= Tick.splitOn or split.set ~= Tick.useSplit or whole.get ~= AntiEsp.wholeOn then
		return false, "The split's or the whole slice's lever goes through no seam of its own module"
	end

	-- 2) Session 3's flip off refuses nothing, finds each cap on, clears them and leaves the split, and the restore
	-- puts back the exact values
	local states: { [string]: boolean }, refused: { string } = Levers.flip(3, false)
	if #refused > 0 then
		return false, `Session 3's flip off refused: {table.concat(refused, ", ")}`
	elseif foundOf(states) ~= FOUND then
		return false, `Session 3's flip off found {foundOf(states)}`
	elseif Step.caps(mounted) ~= NO_CAPS or Tick.splitOn() then
		return false, `After session 3's flip off the caps stood {Step.caps(mounted)}, the split {Tick.splitOn()}`
	end

	local unrestored: { string } = Levers.restore(states)
	if #unrestored > 0 or Step.caps(mounted) ~= CAPS then
		return false, `The restore left the caps {Step.caps(mounted)}, refusing {table.concat(unrestored, ", ")}`
	end

	-- 3) Booted off, a flip on sets each on, the budget before the far rate, and its restore clears each, the far
	-- rate before the budget
	Step.capsOff(mounted)
	states, refused = Levers.flip(3, true)
	if #refused > 0 or Step.caps(mounted) ~= CAPS then
		return false, `From the caps off, the flip on gave {Step.caps(mounted)}, refusing {table.concat(refused, ", ")}`
	end

	unrestored = Levers.restore(states)
	if #unrestored > 0 or Step.caps(mounted) ~= NO_CAPS then
		return false, `From the caps off, the restore left {Step.caps(mounted)}: {table.concat(unrestored, ", ")}`
	end

	-- 4) With the split on, a session's flips off and on and their restores leave it on, and its own name sets it
	Levers.flip(3, true)
	Tick.useSplit(true)
	for _, on: boolean in { false, true } do
		local found: { [string]: boolean } = Levers.flip(3, on)
		Levers.restore(found)
	end

	if not Tick.splitOn() or Step.caps(mounted) ~= CAPS then
		return false, `The session's flips moved the split, on {Tick.splitOn()}, with the caps {Step.caps(mounted)}`
	end

	local alone: { [string]: boolean } = Levers.flip(3, false, "stageSplit")
	if Tick.splitOn() or foundOf(alone) ~= "stageSplit true" or Step.caps(mounted) ~= CAPS then
		return false, `The split's flip by name found {foundOf(alone)}, the caps {Step.caps(mounted)}`
	end

	Levers.restore(alone)
	if not Tick.splitOn() then
		return false, "The split's restore left it off"
	end

	-- 5) The settings' values are what an on sets, never a value of the lever's own
	mounted.settings.relay.budget = 0.0075
	mounted.settings.npcs.budget = 0.0025
	mounted.settings.tiers.underLoad = { runs = 10, scale = 0.25 }
	local cleared: { [string]: boolean } = Levers.flip(3, false)
	Levers.restore(cleared)
	if Step.caps(mounted) ~= CHANGED then
		return false, `With the settings changed, the restore set the caps {Step.caps(mounted)}, not {CHANGED}`
	end

	-- 6) relay.budget off by its name while the far rate stands is refused with the relay's own words, and the budget
	-- stays
	local budget: { [string]: boolean }, held: { string } = Levers.flip(3, false, "relayBudget")
	local line: string = table.concat(held, ", ")
	if #held ~= 1 or string.find(line, "relayBudget refused off: ", 1, true) ~= 1 then
		return false, `relayBudget's flip off by name refused {line}`
	elseif not string.find(line, BUDGET_HELD, 1, true) then
		return false, `relayBudget's refusal gave the relay's reason otherwise: {line}`
	elseif mounted.Relay.budget() ~= 0.0075 or budget.relayBudget ~= true then
		return false, `After the refusal the budget is {mounted.Relay.budget()}, found {budget.relayBudget}`
	end

	-- 7) An on whose key the server started without is refused, naming the key, and sets nothing, and the far rate
	-- with no budget is refused with the relay's own words
	local bare: Step.Mounted = Step.load(answer)
	Step.capsOff(bare)
	bare.settings.antiEsp.whole = nil
	bare.settings.npcs.budget = nil
	bare.settings.relay.budget = nil

	local _, missing: { string } = bare.Levers.flip(3, true)
	local expected: { string } = {
		"antiEspWhole refused on: the dev server started with no antiEsp.whole to set",
		"npcBudget refused on: the dev server started with no npcs.budget to set",
		"relayBudget refused on: the dev server started with no relay.budget to set",
	}

	if #missing ~= 4 or table.concat(missing, "\n", 1, 3) ~= table.concat(expected, "\n") then
		return false, `With no keys, session 3's flip on refused:\n{table.concat(missing, "\n")}`
	elseif string.find(missing[4], "farUnderLoad refused on: ", 1, true) ~= 1 then
		return false, `With no budget, the far rate's refusal read {missing[4]}`
	elseif not string.find(missing[4], NO_BUDGET, 1, true) then
		return false, `With no budget, the far rate's refusal gave the relay's reason otherwise: {missing[4]}`
	elseif Step.caps(bare) ~= NO_CAPS then
		return false, `With no keys, the refused ons set the caps {Step.caps(bare)}`
	end

	bare.settings.tiers.underLoad = nil
	local _, none: { string } = bare.Levers.flip(3, true, "farUnderLoad")
	if table.concat(none, ",") ~= "farUnderLoad refused on: the dev server started with no tiers.underLoad to set" then
		return false, `With no tiers.underLoad, its flip on refused {table.concat(none, ",")}`
	end

	return true, nil
end
