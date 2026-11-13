--[[
    A player who leaves Tread's scope before the game destroys their
    character leaves nothing keyed by them: no connection record and no
    relay view, and nothing more is sent them, while the character stays
    for the game to destroy; their key can build a new character after
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)
	local Relay: any = rig:require(rig.tread.Server.Relay)

	local client: any = rig:require(rig.tread.Network.Client)
	local player: any = rig.mock.players[1]
	client.flush()
	rig:deliver()

	local character: any = server:create(player, rig:at(0, 0))
	local other: any = server:create(rig.mock:addBot("Bot"), rig:at(6, 0))
	rig:tick(TICKS)
	rig:deliver()

	if not Relay.isSent(player, other._slot) then
		return false, "Before the leave the player was not sent the character beside theirs"
	end

	rig.mock:leave(player)

	if Connections.get(player) ~= nil then
		return false, "The player who left still has a connection record"
	elseif Relay.isSent(player, other._slot) then
		return false, "The player who left still has a relay view"
	end

	rig:tick(TICKS)

	if #rig:reportedFor("departed", player) ~= 0 then
		return false, "The server went on sending to the player who left"
	elseif #server:getAll() ~= 2 then
		return false, "The leave took the character away before the game destroyed it"
	end

	character:destroy()

	local again: any = server:create(player, rig:at(0, 0))
	rig:tick(1)
	again:destroy()
	other:destroy()

	if #server:getAll() ~= 0 then
		return false, `After every destroy getAll gave {#server:getAll()} targets`
	end

	return true, nil
end
