--[[
    An idle NPC takes no step and keeps its state whatever command it is
    issued, the rules function never runs for it, and the range query keeps
    it where it stands
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local IDLE_TICKS: number = 5

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local calls: number = 0
	stage.world.rules = function (_: any, _: any): number
		calls += 1

		return math.huge
	end

	local start: vector = vector.create(-20, stage.resting, 0)
	local npc: any = stage.Npcs.create(start, 0)
	stage.Npcs.step(1)

	npc:setAwake(false)
	if npc:isAwake() then
		return false, "An NPC set idle still said it was awake"
	end

	local before: any = stage.State.new()
	stage.State.copy(npc:getState(), before)
	local ran: number = calls

	local order: any = stage.order()
	order.forward = 1
	order.yaw = math.pi / 2
	order.jump = true
	npc:command(order)

	for tick: number = 2, IDLE_TICKS + 1 do
		stage.Npcs.step(tick)
	end

	local state: any = npc:getState()
	if calls ~= ran then
		return false, `The rules ran {calls - ran} times for an idle NPC`
	elseif state.position ~= before.position or state.velocity ~= before.velocity then
		return false, `An idle NPC moved from {before.position} to {state.position}`
	elseif state.facing ~= before.facing or state.jumps ~= before.jumps or state.mode ~= before.mode then
		return false, "An idle NPC turned, jumped or changed mode"
	elseif state.command ~= before.command or state.tick ~= before.tick then
		return false, `An idle NPC's state ran command {state.command} on tick {state.tick}, past its last step's`
	elseif state.groundTicks ~= before.groundTicks or state.airTicks ~= before.airTicks then
		return false, "An idle NPC's timers ran on"
	end

	local found: { number } = stage.Range.npcsNear(state.position, 0)
	if #found ~= 1 or found[1] ~= npc.slot then
		return false, "The range query lost the idle NPC where it stands"
	end

	return true, nil
end
