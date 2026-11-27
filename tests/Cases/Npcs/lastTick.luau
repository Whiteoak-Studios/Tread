--[[
    An NPC steps at the top of the u16 a tick rides in, and its state's
    command number and tick both read that tick
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local LAST_TICK: number = 2 ^ 16 - 1 -- The top of a u16

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, 0), 0)
	stage.Npcs.step(LAST_TICK)

	local state: any = npc:getState()
	if state.command ~= LAST_TICK or state.tick ~= LAST_TICK then
		return false, `Stepped at tick {LAST_TICK}, its state read command {state.command} on tick {state.tick}`
	end

	return true, nil
end
