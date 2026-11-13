--[[
    Npcs.step takes the tick as the u16 it rides in, refusing one past the
    top of that u16 and one between two whole ticks, and leaving every NPC
    unstepped by a refused call
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local PAST_U16: number = 2 ^ 16 -- One past the top of a u16
local FRACTION: number = 2.5
local REFUSAL: string = `at most {PAST_U16 - 1}`

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, 0), 0)

	for _, tick: number in { PAST_U16, FRACTION } do
		local ran: boolean, message: any = pcall(stage.Npcs.step, tick)
		if ran then
			return false, `Npcs.step took the tick {tick}`
		elseif not string.find(`{message}`, REFUSAL, 1, true) or not string.find(`{message}`, `{tick}`, 1, true) then
			return false, `Npcs.step refused the tick {tick} without naming it and the u16's top: {message}`
		end
	end

	if npc:getState().tick ~= 0 or npc:getState().command ~= 0 then
		return false, "A refused tick still stepped the NPC"
	end

	return true, nil
end
