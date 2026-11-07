--[[
    A rules function that throws for one NPC leaves only that NPC unstepped,
    put back as it was before the tick, reports the npcs stage, and the NPCs
    after it still step; once it stops throwing, the NPC steps again
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local WEST: number = math.pi / 2 -- A yaw that looks along -X

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	-- The rules write the block before they throw, so a body put back shows its block put back too
	stage.world.rules = function (step: any, _: any): number
		local block: { [string]: any } = step.block
		block.count += 1

		if block.throws then
			error("These rules throw for this NPC")
		end

		return math.huge
	end

	local npcs: { any } = {}
	for index: number = 1, 3 do
		local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, index * 6), 0)
		npc:getState().block.count = 0
		table.insert(npcs, npc)
	end

	-- One tick on no input settles them on the floor, where a jump can be pressed
	stage.Npcs.step(1)

	local thrower: any = npcs[2]
	thrower:getState().block.throws = true

	local order: any = stage.order()
	order.forward = 1
	order.yaw = WEST
	order.jump = true

	for _, npc: any in npcs do
		npc:command(order)
	end

	local before: any = stage.State.new()
	stage.State.copy(thrower:getState(), before)

	stage.Npcs.step(2)

	local state: any = thrower:getState()
	if state.position ~= before.position or state.velocity ~= before.velocity then
		return false, `The NPC whose rules threw moved from {before.position} to {state.position}`
	elseif state.facing ~= before.facing or state.jumps ~= before.jumps or state.grounded ~= before.grounded then
		return false, `The NPC whose rules threw turned to {state.facing} or jumped`
	elseif state.command ~= before.command or state.tick ~= before.tick then
		return false, `The NPC whose rules threw kept command {state.command} on tick {state.tick} from its failed step`
	elseif state.block.count ~= before.block.count then
		return false, `The NPC whose rules threw kept the block its failed step wrote, a count of {state.block.count}`
	end

	for _, index: number in { 1, 3 } do
		local other: any = npcs[index]:getState()
		if other.tick ~= 2 or other.block.count ~= 2 or other.jumps ~= 1 then
			return false, `NPC {index} did not step beside the one that threw`
		end
	end

	if #stage.reports ~= 1 then
		return false, `The failed step gave {#stage.reports} reports, not one`
	end

	local report: any = stage.reports[1]
	if report.player ~= nil or report.kind ~= "stage" or report.measurement ~= "npcs" then
		return false, `The failed step was reported as {report.kind} {report.measurement}, not the npcs stage`
	end

	-- Its press waited, so the step it takes once its rules stop throwing jumps
	state.block.throws = false
	stage.Npcs.step(3)

	if state.tick ~= 3 or state.block.count ~= 2 or state.jumps ~= 1 or state.facing == before.facing then
		return false, "The NPC whose rules threw did not step, turn and jump once they stopped throwing"
	elseif #stage.reports ~= 1 then
		return false, "A step that ran was reported"
	end

	return true, nil
end
