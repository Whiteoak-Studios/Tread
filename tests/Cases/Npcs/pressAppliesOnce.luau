--[[
    A press in an NPC's command applies once while its level repeats: a
    held jump jumps once, a command that holds it again is no press, and a
    release and a press issued before one step still jump
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local JUMP_TICKS: number = 30 -- Long enough for a jump to rise, fall and land

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, -10), 0)
	stage.Npcs.step(1)

	local order: any = stage.order()
	order.jump = true
	npc:command(order)

	local tick: number = 1
	for _ = 1, JUMP_TICKS do
		tick += 1
		stage.Npcs.step(tick)
	end

	local state: any = npc:getState()
	if state.jumps ~= 1 or state.lands ~= 1 or not state.grounded then
		return false, `A held jump gave {state.jumps} jumps and {state.lands} landings, not one of each`
	end

	-- The same level issued again is no press
	npc:command(order)
	tick += 1
	stage.Npcs.step(tick)
	if state.jumps ~= 1 or not state.grounded then
		return false, "A jump level held over from the command before jumped again"
	end

	-- A release then a press before the next step is still a press
	local release: any = stage.order()
	npc:command(release)
	npc:command(order)
	tick += 1
	stage.Npcs.step(tick)

	if state.jumps ~= 2 or state.grounded then
		return false, `A release and a press issued between two steps gave {state.jumps} jumps in all, not 2`
	end

	return true, nil
end
