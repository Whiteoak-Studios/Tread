--[[
    Destroying an NPC gives its slot back to the slot table and takes it out
    of the range query, the stage and each, and leaves every other NPC be
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local gone: vector = vector.create(-20, stage.resting, 0)
	local kept: vector = vector.create(-20, stage.resting, 10)
	local doomed: any = stage.Npcs.create(gone, 0)
	local other: any = stage.Npcs.create(kept, 0)

	if stage.Slots.count("Npc") ~= 2 then
		return false, `Two NPCs held {stage.Slots.count("Npc")} NPC slots`
	end

	doomed:destroy()

	local freed: boolean, message: any = pcall(stage.Slots.release, doomed.slot)
	if stage.Slots.count("Npc") ~= 1 then
		return false, `After one of two was destroyed the NPCs held {stage.Slots.count("Npc")} slots, not 1`
	elseif freed or not string.find(`{message}`, "takes a taken slot", 1, true) then
		return false, `The destroyed NPC's slot {doomed.slot} was still taken: {message}`
	elseif #stage.Range.npcsNear(gone, 1) ~= 0 then
		return false, "The range query still held the destroyed NPC"
	elseif #stage.Range.npcsNear(kept, 1) ~= 1 then
		return false, "Destroying one NPC took the other out of the range query"
	end

	local visited: { any } = {}
	stage.Npcs.each(function (npc: any)
		table.insert(visited, npc)
	end)

	if #visited ~= 1 or visited[1] ~= other then
		return false, `Npcs.each visited {#visited} NPCs after a destroy, not the one left`
	end

	stage.Npcs.step(1)

	if doomed:getState().tick ~= 0 then
		return false, "The destroyed NPC still stepped"
	elseif other:getState().tick ~= 1 then
		return false, "The NPC left did not step"
	end

	return true, nil
end
