--[[
    The NPC budget run takes S4Npcs alone, before then after, with the NPCs'
    budget flipped alone through its own lever and every other lever as the
    server has it, its table titled by its load, and the budget put back
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local LOAD: string = "S4Npcs"
local NAME: string = "npcBudget"
local TITLE: string = "Step benchmark NPC budget run session 3, "
local BUDGET: number = 0.001 -- The NPCs' budget as the stand-in server's settings hold it

-- The caps a half asks for: the NPCs' budget off before and on after, and the other three as the server has them
local BEFORE: string = "true nil 0.005 20/0.5"
local AFTER: string = "true 0.001 0.005 20/0.5"

-- Each half drives and gives its figures
local function answer(_: string, _: string?): (boolean, string, { [string]: number }?)
	return true, "drove and cleaned up", { skipped = 1 }
end

return function (): (boolean, string | nil)
	-- 1) Through its scenario: S4Npcs before then after on the workers, the budget alone off then on, every other
	-- lever as the server started them, then its table, and the budget put back
	local mounted: Step.Mounted = Step.load(answer)
	local passed: boolean, reason: string? = mounted.BenchStepNpcs()
	local order: string = table.concat(mounted.events, "\n", 2, 3)
	local closing: string? = mounted.events[4]
	if not passed then
		return false, `An NPC budget run whose halves drove failed: {reason}`
	elseif order ~= `half {LOAD}/before\nhalf {LOAD}/after` or #mounted.events ~= 4 then
		return false, `The NPC budget run went:\n{table.concat(mounted.events, "\n")}`
	elseif not closing or string.find(closing, `{LOAD} table, figure: before after change percent\n`, 1, true) ~= 1 then
		return false, `The NPC budget run closed on:\n{closing}`
	end

	for index: number, half: string in { "before", "after" } do
		local asked: Step.Asked = mounted.asked[index]
		local caps: string = half == "after" and AFTER or BEFORE
		if asked.scenario ~= LOAD or asked.half ~= half or asked.workers ~= true then
			return false, `The NPC budget run's half {index} was {asked.scenario}/{asked.half}`
		elseif Step.asked(asked) ~= caps then
			return false, `The NPC budget run's {half} half ran with the caps {Step.asked(asked)}`
		elseif asked.split or asked.bands ~= 3 or not asked.crowd or asked.antiEsp or asked.memory then
			return false, `The NPC budget run's {half} half ran with a lever of session 2 or the split otherwise`
		end
	end

	if mounted.Npcs.budget() ~= BUDGET then
		return false, `The NPC budget run left the budget {mounted.Npcs.budget()}`
	end

	-- 2) The header: its title, no note of the split, and the budget named off before and on after
	local header: string = mounted.events[1]
	local at: number? = string.find(header, "; after: ", 1, true)
	local before: string = string.sub(header, 1, at or 0)
	local after: string = string.sub(header, at or #header + 1)
	if string.sub(header, 1, #TITLE) ~= TITLE or string.find(header, "with stageSplit on", 1, true) then
		return false, `The NPC budget run's header read:\n{header}`
	elseif not string.find(before, `{NAME} (session 3, live) off, `, 1, true) then
		return false, `The NPC budget run's header named no before half with the budget off:\n{header}`
	elseif not string.find(after, `{NAME} (session 3, live) on, `, 1, true) then
		return false, `The NPC budget run's header named no after half with the budget on:\n{header}`
	end

	-- 3) Started with the budget off, both halves still run off then on, and it is put back off
	local opposite: Step.Mounted = Step.load(answer)
	opposite.Npcs.setBudget(nil)
	opposite.BenchStep("npcs")
	if opposite.Npcs.budget() ~= nil then
		return false, `An NPC budget run started with the budget off left it {opposite.Npcs.budget()}`
	elseif Step.asked(opposite.asked[1]) ~= BEFORE or Step.asked(opposite.asked[2]) ~= AFTER then
		return false, "An NPC budget run started with the budget off ran its halves otherwise"
	end

	return true, nil
end
