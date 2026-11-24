--[[
    A press issued to an NPC that then waits is kept through the wait and
    applied on its next step, once: a jump pressed before a waiting tick
    jumps on the tick after, and its held level jumps no more
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 0 -- Spent at the first read, so the NPC steps every other tick
local JUMP_TICKS: number = 30 -- Steps enough for a jump to rise, fall and land

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	-- One tick with the cap off settles it on the floor, where a jump can be pressed
	local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, -10), 0)
	stage.Npcs.step(1)

	local order: any = stage.order()
	order.jump = true
	npc:command(order)
	stage.Npcs.setBudget(BUDGET)

	stage.Npcs.step(2)

	local state: any = npc:getState()
	if state.tick ~= 1 then
		return false, `The NPC stepped on tick {state.tick} under a spent budget, where it waits`
	elseif state.jumps ~= 0 or not state.grounded then
		return false, "The NPC jumped on the tick it waited"
	end

	stage.Npcs.step(3)
	if state.tick ~= 3 or state.jumps ~= 1 or state.grounded or state.velocity.y <= 0 then
		return false,
			`The step after the wait gave {state.jumps} jumps, rising at {state.velocity.y}, not the jump pressed`
	end

	-- Stepping every other tick, it lands once, and the level it still holds is no press
	local tick: number = 3
	for _ = 1, 2 * JUMP_TICKS do
		tick += 1
		stage.Npcs.step(tick)
	end

	if state.jumps ~= 1 or state.lands ~= 1 or not state.grounded then
		return false, `The press kept through a wait gave {state.jumps} jumps and {state.lands} landings, not one each`
	elseif #stage.landings ~= 1 or stage.landings[1].npc ~= npc then
		return false, `The jump's landing reached the callback {#stage.landings} times, not once`
	end

	return true, nil
end
