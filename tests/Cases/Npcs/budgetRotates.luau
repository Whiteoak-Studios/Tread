--[[
    Under a budget the walk starts at the first NPC that waited the tick
    before, so the waits move round the NPCs from tick to tick and none
    waits two ticks running
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 1.5 -- Spent at a walk's third read, so one NPC not forced steps a tick
local COUNT: number = 4
local SPACING: number = 10 -- Studs between the NPCs along Z

-- The slots that waited each tick, worked out from the cursor's rule: on the odd ticks the one NPC not forced that
-- steps moves on a slot each time, and on the even ticks every NPC that waited steps beside it
local WAITS: { string } = { "1 2 3", "", "0 2 3", "", "0 1 3", "", "0 1 2", "" }

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	local npcs: { any } = {}
	for index: number = 1, COUNT do
		table.insert(npcs, stage.Npcs.create(vector.create(-20, stage.resting, (index - 2) * SPACING), 0))
	end

	stage.Npcs.setBudget(BUDGET)

	for tick: number, expected: string in WAITS do
		stage.Npcs.step(tick)

		local waited: { string } = {}
		for _, npc: any in npcs do
			if npc:getState().tick ~= tick then
				table.insert(waited, `{npc.slot}`)
			end
		end

		local slots: string = table.concat(waited, " ")
		if slots ~= expected then
			return false, `On tick {tick} the NPCs in slots "{slots}" waited, not "{expected}"`
		end
	end

	return true, nil
end
