--[[
    A budget cleared straight after a tick in which NPCs waited steps every
    NPC with no clock read; set again, the walk starts at the cursor it had,
    and the NPCs that waited step forced on their first budgeted turn
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local ONE: number = 1.5 -- Spent at a walk's third read, so one NPC not forced steps a tick
local COUNT: number = 4
local SPACING: number = 10 -- Studs between the NPCs along Z
local OFF_TICKS: number = 2 -- Ticks run with the budget cleared

-- Steps one tick and gives the slots of the NPCs that did not step on it, in slot order, as one line
local function waits(stage: any, npcs: { any }, tick: number): string
	stage.Npcs.step(tick)

	local slots: { string } = {}
	for _, npc: any in npcs do
		if npc:getState().tick ~= tick then
			table.insert(slots, `{npc.slot}`)
		end
	end

	return table.concat(slots, " ")
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local clock: any = stage.clock(STEP)
	stage.start(clock.read)

	local npcs: { any } = {}
	for index: number = 1, COUNT do
		table.insert(npcs, stage.Npcs.create(vector.create(-20, stage.resting, (index - 2) * SPACING), 0))
	end

	stage.Npcs.setBudget(ONE)

	local tick: number = 1
	local slots: string = waits(stage, npcs, tick)
	if slots ~= "1 2 3" then
		return false, `The budgeted tick's waits fell on slots "{slots}", not "1 2 3"`
	end

	local reads: number = clock.reads
	local waited: number = stage.Npcs.waited()
	stage.Npcs.setBudget(nil)

	for _ = 1, OFF_TICKS do
		tick += 1
		slots = waits(stage, npcs, tick)
		if slots ~= "" then
			return false, `With the budget cleared, the NPCs in slots "{slots}" did not step on tick {tick}`
		end
	end

	if clock.reads ~= reads then
		return false, `The ticks with the budget cleared read the clock {clock.reads - reads} times, not 0`
	elseif stage.Npcs.waited() ~= waited then
		return false, `The ticks with the budget cleared moved Npcs.waited from {waited} to {stage.Npcs.waited()}`
	end

	-- From the cursor at slot 1, the three that waited step forced and the one not forced has the budget to step
	stage.Npcs.setBudget(ONE)
	tick += 1
	slots = waits(stage, npcs, tick)
	if slots ~= "" then
		return false, `On the first tick with the budget set again, the NPCs in slots "{slots}" waited, not none`
	end

	-- Then an ordinary tick from the same cursor: slot 1 steps and the rest wait
	tick += 1
	slots = waits(stage, npcs, tick)
	if slots ~= "0 2 3" then
		return false, `On the second tick with the budget set again, slots "{slots}" waited, not "0 2 3"`
	end

	return true, nil
end
