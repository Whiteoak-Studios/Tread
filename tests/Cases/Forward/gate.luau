--[[
    The forward gates a player as the kit gates itself: in Studio anyone is
    sent their reports, and outside it only a player whose UserId the
    exploiter list has, while a player it doesn't list is sent none
--]]

--!strict
local Server = require("../../Fixtures/Exploits/Server")

-- Whether a report about the player who joins writes anything for them, in Studio or not, listed or not
local function sent(studio: boolean, listed: boolean): boolean
	local rig: Server.Rig = Server.load()
	local loaded: any = rig.loaded
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	rig.studio(studio)
	local fire: (player: any, kind: string, measurement: number | string) -> () = rig.start()

	-- The mock numbers its players' UserIds from 1, and the gate is read as the player joins
	if listed then
		table.insert(rig.exploiters.users, 1)
	end

	loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]
	if player.UserId ~= 1 then
		error(`The mock's first player has UserId {player.UserId}, not 1`)
	end

	-- What a report writes waits for the next flush, so the player's pending bytes show whether one was written
	fire(player, "standIn", 1)
	local _, pending: number = rig.network.traffic(player)

	return pending > 0
end

return function (): (boolean, string | nil)
	if not sent(true, false) then
		return false, "In Studio a player the list doesn't have was sent no report"
	elseif not sent(false, true) then
		return false, "Outside Studio a player the list has was sent no report"
	elseif sent(false, false) then
		return false, "Outside Studio a player the list doesn't have was sent a report"
	end

	return true, nil
end
