--[[
    Waking an idle NPC steps it again from the command issued while it was
    idle, the jump pressed then applying on its first step back
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local START_Z: number = 0
local TOLERANCE: number = 0.005 -- A quarter of the 0.02-stud skin

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, START_Z), 0)
	stage.Npcs.step(1)
	npc:setAwake(false)

	local order: any = stage.order()
	order.forward = 1
	npc:command(order)
	stage.Npcs.step(2)
	stage.Npcs.step(3)

	local idle: vector = npc:getState().position
	if math.abs(idle.z - START_Z) > TOLERANCE then
		return false, `An idle NPC moved to {idle} before it woke`
	end

	npc:setAwake(true)
	if not npc:isAwake() then
		return false, "A woken NPC still said it was idle"
	end

	-- Walking on, it walks the walk speed's distance each tick it steps
	stage.Npcs.step(4)
	stage.Npcs.step(5)

	local state: any = npc:getState()
	local walked: number = 2 * stage.world.settings.walk * stage.world.delta
	if math.abs(state.position.z - (START_Z - walked)) > TOLERANCE then
		return false, `The woken NPC ended at {state.position}, not {walked} studs on along -Z`
	elseif state.tick ~= 5 then
		return false, `The woken NPC's last step ran on tick {state.tick}, not 5`
	end

	-- A jump pressed while idle waits for the step that wakes it
	npc:setAwake(false)
	order.jump = true
	npc:command(order)
	stage.Npcs.step(6)
	if npc:getState().jumps ~= 0 then
		return false, "An idle NPC jumped"
	end

	npc:setAwake(true)
	stage.Npcs.step(7)

	local jumped: any = npc:getState()
	if jumped.jumps ~= 1 or jumped.grounded or jumped.velocity.y <= 0 then
		return false, `The jump pressed while idle gave {jumped.jumps} jumps on waking, rising at {jumped.velocity.y}`
	end

	return true, nil
end
