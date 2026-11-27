--[[
    In Studio, where the kit is for anyone, only real players the dev scope
    has joined are sent their reports: one about no player or a bot writes
    nothing, one about a player who left writes nothing and raises no
    failure, and a second start fails
--]]

--!strict
local Server = require("../../Fixtures/Exploits/Server")

return function (): (boolean, string | nil)
	local rig: Server.Rig = Server.load()
	local loaded: any = rig.loaded
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared
	local Network: any = rig.network

	rig.studio(true)
	local fire: (player: any, kind: string, measurement: number | string) -> () = rig.start()

	local again: boolean = pcall(rig.forward.start, { onReport = function () end })
	if again then
		return false, "A second start was taken"
	end

	loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]
	local bot: any = loaded.mock:addBot("Bot")

	local failures: { string } = {}
	Network.onFailure(function (_: any, kind: string, _: string)
		table.insert(failures, kind)
	end)

	-- What a report writes waits for the next flush, so a player's pending bytes show whether one was written
	fire(nil, "stuck", 1)
	fire(bot, "standIn", 1)
	local _, botPending: number = Network.traffic(bot)
	if botPending ~= 0 then
		return false, `A report about a bot wrote {botPending} bytes for it`
	end

	fire(player, "standIn", 1)
	local _, pending: number = Network.traffic(player)
	if pending == 0 then
		return false, "A report about a real player wrote nothing for them"
	end

	Network.flush()
	loaded.mock:leave(player)
	fire(player, "standIn", 2)
	if #failures ~= 0 then
		return false, `A report about a player who left raised a {failures[1]} failure`
	end

	return true, nil
end
