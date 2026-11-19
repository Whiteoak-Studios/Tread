--[[
    The NPCs step in slot order, not the order they were made in, after the
    players the case steps first, and each visits them in the same order
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local CONSTANTS: string = "src/Constants.luau"
local PLAYER: string = "player" -- The label a player's rule-state block carries

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local slots: number = Environment.load(CONSTANTS).SLOTS
	stage.start()

	local order: { string } = {}
	stage.world.rules = function (step: any, _: any): number
		table.insert(order, `{step.block.label}`)

		return math.huge
	end

	-- Slots 0 to 2, then slot 0 back once every never-used slot is taken, so the last made holds the lowest
	local resting: number = stage.resting
	local first: any = stage.Npcs.create(vector.create(-20, resting, -10), 0)
	local second: any = stage.Npcs.create(vector.create(-20, resting, 0), 0)
	local third: any = stage.Npcs.create(vector.create(-20, resting, 10), 0)
	first:destroy()

	for _ = 3, slots - 1 do
		stage.Slots.take("Body")
	end

	local last: any = stage.Npcs.create(vector.create(-20, resting, 20), 0)
	if second.slot ~= 1 or third.slot ~= 2 or last.slot ~= 0 then
		return false, `The NPCs took slots {second.slot}, {third.slot} and {last.slot}, not 1, 2 and 0`
	end

	for _, npc: any in { second, third, last } do
		npc:getState().block.label = npc.slot
	end

	-- The players step first, as the simulate stage steps them before the npcs stage
	for index: number = 1, 2 do
		local player: any = stage.State.new()
		player.position = vector.create(0, resting, index * 10)
		player.block.label = PLAYER

		local command: any = stage.order()
		command.number = 1
		command.pressed = { jump = false, crouch = false, sprint = false, aim = false }
		stage.Step.advance(player, command, stage.world)
	end

	stage.Npcs.step(1)

	local stepped: string = table.concat(order, " ")
	if stepped ~= "player player 0 1 2" then
		return false, `The bodies stepped as {stepped}, not the players then the NPCs by slot`
	end

	local visited: { string } = {}
	stage.Npcs.each(function (npc: any)
		table.insert(visited, `{npc.slot}`)
	end)

	local each: string = table.concat(visited, " ")
	if each ~= "0 1 2" then
		return false, `Npcs.each visited {each}, not the NPCs by slot`
	end

	return true, nil
end
