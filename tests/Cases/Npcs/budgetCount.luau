--[[
    Npcs.waited counts each NPC step a budget made wait, a running total
    from start that a forced step, a step with the cap off and a step that
    throws add nothing to, and a throwing NPC under a budget stops no other
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local ONE: number = 1.5 -- Spent at a walk's third read, so one NPC not forced steps a tick
local THREE: number = 3.5 -- Spent at a walk's fifth read, so three do
local COUNT: number = 4
local SPACING: number = 10 -- Studs between the NPCs along Z

-- The running count after each tick under ONE from the cursor at slot 0: three of the four wait on the odd ticks,
-- and on the even ticks those three step forced beside the fourth
local TOTALS: { number } = { 3, 3, 6, 6, 9, 9, 12, 12 }

-- The slots that stepped on a tick, in slot order, as one line
local function stepped(npcs: { any }, tick: number): string
	local slots: { string } = {}
	for _, npc: any in npcs do
		if npc:getState().tick == tick then
			table.insert(slots, `{npc.slot}`)
		end
	end

	return table.concat(slots, " ")
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	stage.world.rules = function (step: any, _: any): number
		if step.block.throws then
			error("These rules throw for this NPC")
		end

		return math.huge
	end

	local npcs: { any } = {}
	for index: number = 1, COUNT do
		table.insert(npcs, stage.Npcs.create(vector.create(-20, stage.resting, (index - 2) * SPACING), 0))
	end

	stage.Npcs.step(1)
	if stage.Npcs.waited() ~= 0 then
		return false, `A tick with the cap off counted {stage.Npcs.waited()} waits, not 0`
	end

	stage.Npcs.setBudget(ONE)

	local tick: number = 1
	for _, total: number in TOTALS do
		tick += 1
		stage.Npcs.step(tick)

		if stage.Npcs.waited() ~= total then
			return false, `After tick {tick} Npcs.waited gave {stage.Npcs.waited()}, not {total}`
		end
	end

	-- Every NPC stepped on the last tick, so clearing the budget leaves none waiting, and the total stays
	local total: number = TOTALS[#TOTALS]
	stage.Npcs.setBudget(nil)
	tick += 1
	stage.Npcs.step(tick)
	if stage.Npcs.waited() ~= total then
		return false, `Clearing the budget left Npcs.waited at {stage.Npcs.waited()}, not the {total} it had`
	elseif #stage.reports ~= 0 then
		return false, `The NPCs gave {#stage.reports} reports before any threw`
	end

	-- From the cursor at slot 0: slot 0 steps, slot 1 throws, which is no wait, slot 2 steps and slot 3 waits
	npcs[2]:getState().block.throws = true
	stage.Npcs.setBudget(THREE)
	tick += 1
	stage.Npcs.step(tick)

	local thrown: number = total + 1 -- The wait of the NPC in slot 3, the one beside the throw
	if stepped(npcs, tick) ~= "0 2" then
		return false, `Beside the NPC that threw, the NPCs in slots "{stepped(npcs, tick)}" stepped, not 0 and 2`
	elseif stage.Npcs.waited() ~= thrown then
		return false, `A tick with a throw and one wait left Npcs.waited at {stage.Npcs.waited()}, not {thrown}`
	elseif #stage.reports ~= 1 or stage.reports[1].kind ~= "stage" or stage.reports[1].measurement ~= "npcs" then
		return false, `The throw under a budget gave {#stage.reports} reports, not one of the npcs stage`
	end

	-- From slot 3: slot 3 steps forced, slot 0 steps, slot 1 throws again and slot 2 after it still steps
	tick += 1
	stage.Npcs.step(tick)

	if stepped(npcs, tick) ~= "0 2 3" then
		return false, `The tick after, the NPCs in slots "{stepped(npcs, tick)}" stepped, not 0, 2 and 3`
	elseif stage.Npcs.waited() ~= thrown then
		return false, `A forced step and a throw moved Npcs.waited to {stage.Npcs.waited()}, not the {thrown} it had`
	elseif #stage.reports ~= 2 then
		return false, `The second throw gave {#stage.reports - 1} reports, not one`
	end

	return true, nil
end
