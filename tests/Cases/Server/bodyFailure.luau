--[[
    Each body steps under a pcall of its own: a character whose pre-command
    hook throws, and one whose rules throw inside its step, are each left
    where they stood and reported as stage simulate with their bot, an NPC
    whose rules throw is reported as stage npcs with no player, and the
    character between them still steps every tick
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 6

return function (): (boolean, string | nil)
	local hooked: any = nil

	local rig: Rig.Rig = Rig.new(function (shared: any, settings: any)
		settings.beforeCommand = function (character: any, _: any)
			if character.player == hooked then
				error("This pre-command hook throws on purpose, for one character")
			end
		end

		shared.rules = function (step: any, _: any): number
			if step.isNpc or step.fields.beingRevived then
				error("These rules throw on purpose, for NPCs and for a character being revived")
			end

			return math.huge
		end
	end)

	local server: any = rig:start()
	hooked = rig.mock:addBot("Hooked")
	local revived: any = rig.mock:addBot("Revived")
	local fine: any = rig.mock:addBot("Fine")

	local hookedCharacter: any = server:create(hooked, rig:at(-6, 0))
	local revivedCharacter: any = server:create(revived, rig:at(0, 0))
	local fineCharacter: any = server:create(fine, rig:at(6, 0))
	server:createNpc(rig:at(-12, 0))
	revivedCharacter:setField("beingRevived", true)

	local built: number = rig:at(0, 0).Position.Y
	rig:tick(TICKS)

	if hookedCharacter:getState().root.Y ~= built then
		return false, "The character whose hook threw moved"
	elseif revivedCharacter:getState().root.Y ~= built then
		return false, "The character whose rules threw inside its step was not put back as it stood"
	elseif not fineCharacter:getState().grounded then
		return false, "The character between the two that threw never stepped onto the floor"
	end

	for _, bot: any in { hooked, revived } do
		local reports: { Rig.Heard } = rig:reportedFor("stage", bot)
		if #reports ~= TICKS or reports[1].measurement ~= "simulate" then
			return false, `{bot.Name}'s failed steps gave {#reports} stage reports, not one a tick naming simulate`
		end
	end

	if #rig:reportedFor("stage", fine) ~= 0 then
		return false, "The character that stepped cleanly was reported"
	end

	local npcReports: { Rig.Heard } = rig:reportedFor("stage", nil)
	if #npcReports ~= TICKS or npcReports[1].measurement ~= "npcs" then
		return false,
			`The NPC's failed steps gave {#npcReports} stage reports with no player, not one a tick naming npcs`
	end

	return true, nil
end
