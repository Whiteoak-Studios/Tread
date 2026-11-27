--[[
    Under a budget an NPC that waited steps on its next turn whatever the
    time, an NPC the walk reaches after the budget is spent included, and
    it takes that one step alone: the tick it waited is not made up
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 0 -- Spent at the first read, so every NPC that may wait does
local COUNT: number = 3
local SPACING: number = 10 -- Studs between the NPCs along Z

-- How many steps each NPC has taken, in slot order, as one line
local function steps(npcs: { any }): string
	local counts: { string } = {}
	for _, npc: any in npcs do
		table.insert(counts, `{npc:getState().block.count}`)
	end

	return table.concat(counts, " ")
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	stage.world.rules = function (step: any, _: any): number
		local block: { [string]: any } = step.block
		block.count += 1

		return math.huge
	end

	-- Slots 0, 1 and 2, the second idle through the first tick so it is the one not forced on the second
	local npcs: { any } = {}
	for index: number = 1, COUNT do
		local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, (index - 1) * SPACING), 0)
		npc:getState().block.count = 0
		table.insert(npcs, npc)
	end

	stage.Npcs.setBudget(BUDGET)
	npcs[2]:setAwake(false)

	stage.Npcs.step(1)
	if steps(npcs) ~= "0 0 0" then
		return false, `A spent budget on the first tick left the NPCs with {steps(npcs)} steps, not none`
	end

	-- The NPC in slot 1 waits, and the one in slot 2 after it still steps, since it waited on the first tick
	npcs[2]:setAwake(true)
	stage.Npcs.step(2)
	if steps(npcs) ~= "1 0 1" then
		return false, `The second tick left the NPCs with {steps(npcs)} steps, not 1 0 1`
	end

	for _, index: number in { 1, 3 } do
		local state: any = npcs[index]:getState()
		if state.tick ~= 2 or state.command ~= 2 then
			return false, `NPC {index}'s forced step ran command {state.command} on tick {state.tick}, not tick 2's`
		end
	end

	stage.Npcs.step(3)
	if steps(npcs) ~= "1 1 1" then
		return false, `The third tick left the NPCs with {steps(npcs)} steps, not 1 1 1`
	end

	stage.Npcs.step(4)
	if steps(npcs) ~= "2 1 2" then
		return false, `The fourth tick left the NPCs with {steps(npcs)} steps, not 2 1 2`
	end

	return true, nil
end
