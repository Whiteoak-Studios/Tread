--[[
    server:create errors, naming the held-back count, when no slot is free,
    and refuses a bot on a server whose settings give no bots.rtt, each
    leaving no slot taken and no connection record behind
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SLOTS: number = 4096 -- Every slot the table holds, which bodies fill
local HELD: string = "slots.reserve holds back" -- How the full table's refusal names the reserve

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)
	local Slots: any = rig:require(rig.tread.Server.Slots)

	for _ = 1, SLOTS do
		Slots.take("Body")
	end

	local bot: any = rig.mock:addBot("Bot")
	local built: boolean, message: any = pcall(server.create, server, bot, rig:at(0, 0))
	if built then
		return false, "server:create built a character with no slot free"
	elseif not string.find(tostring(message), `{HELD} {rig.settings.slots.reserve}`, 1, true) then
		return false, `The full table's refusal named no held-back count: {message}`
	elseif Connections.get(bot) ~= nil or #server:getAll() ~= 0 then
		return false, "The refused create left a connection record or a character"
	end

	-- A server whose settings give no bot round trip
	local plain: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.bots = nil
	end)

	local plainServer: any = plain:start()
	local plainSlots: any = plain:require(plain.tread.Server.Slots)
	local refused: boolean = pcall(plainServer.create, plainServer, plain.mock:addBot("Bot"), plain:at(0, 0))

	if refused then
		return false, "server:create took a bot on a server with no bots.rtt"
	elseif plainSlots.count("Player") ~= 0 then
		return false, "The refused bot's create left a slot taken"
	end

	return true, nil
end
