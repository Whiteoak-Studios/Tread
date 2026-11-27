--[[
    An NPC steps every tick from the last command the server issued it, its
    held move repeating, as an NPC the rules function is told of, and the
    range query follows it
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local TICKS: number = 10 -- Ticks it walks on the one command
local START_Z: number = 10
local TOLERANCE: number = 0.005 -- A quarter of the 0.02-stud skin

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local calls: number, npcCalls: number = 0, 0
	stage.world.rules = function (step: any, _: any): number
		calls += 1
		if step.isNpc then
			npcCalls += 1
		end

		return math.huge
	end

	local start: vector = vector.create(-20, stage.resting, START_Z)
	local npc: any = stage.Npcs.create(start, 0)
	if not npc:getState().npc then
		return false, "A new NPC's state was not marked an NPC's"
	end

	-- One tick on no input settles it on the floor, then one command walks it ahead along -Z
	stage.Npcs.step(1)

	local order: any = stage.order()
	order.forward = 1
	npc:command(order)

	for tick: number = 2, TICKS + 1 do
		stage.Npcs.step(tick)
	end

	local state: any = npc:getState()
	local walked: number = TICKS * stage.world.settings.walk * stage.world.delta
	local at: vector = state.position

	if math.abs(at.z - (START_Z - walked)) > TOLERANCE or math.abs(at.x - start.x) > TOLERANCE then
		return false, `It walked to {at}, where {walked} studs along -Z from {start} was expected`
	elseif math.abs(at.y - stage.resting) > TOLERANCE or not state.grounded or state.mode ~= "Ground" then
		return false, `It ended at a height of {at.y}, grounded {state.grounded}, in {state.mode}, not on the floor`
	elseif state.velocity.z ~= -stage.world.settings.walk then
		return false, `It ended walking at {state.velocity.z} along Z, not the walk speed`
	elseif calls ~= TICKS + 1 or npcCalls ~= calls then
		return false, `The rules ran {calls} times, {npcCalls} told of an NPC, not {TICKS + 1} told of one`
	elseif state.command ~= TICKS + 1 or state.tick ~= TICKS + 1 then
		return false, `Its last step ran command {state.command} on tick {state.tick}, not the tick it ran on`
	end

	local found: { number } = stage.Range.npcsNear(at, 0)
	if #found ~= 1 or found[1] ~= npc.slot then
		return false, `The range query found {#found} NPCs where it stands, not its slot alone`
	elseif #stage.Range.npcsNear(start, 1) ~= 0 then
		return false, "The range query still held it where it was made"
	end

	return true, nil
end
