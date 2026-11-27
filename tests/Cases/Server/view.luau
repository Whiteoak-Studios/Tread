--[[
    The server hears each client's View: its start refuses settings that
    give View no rate, a player whose client sends 400 studs is sent a
    character at 300 and not one at 600, a bot, which sends none, keeps the
    whole radius, and Views past the rate's burst are refused and reported
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local MISSING: string = "server.rates.view"
local DISTANCE: number = 400
local NEAR: number = 300
local FAR: number = 600
local TICKS: number = 6 -- Enough for anti-ESP's first tests and the reveals or hides after them

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local rate: any = rig.settings.rates.view
	rig.settings.rates.view = nil

	local taken: boolean, message: any = pcall(rig.Server.start, rig.shared, rig.settings)
	if taken then
		return false, "Server.start took server settings that give View no rate"
	elseif not string.find(tostring(message), MISSING, 1, true) then
		return false, `Server.start's refusal of the missing rate named something else: {message}`
	end

	rig.settings.rates.view = rate
	local server: any = rig:start()
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local network: any = rig:require(rig.tread.Network.Client)

	-- The mock's player joins once its client side's handshake crosses
	network.flush()
	rig:deliver()

	local player: any = rig.mock.players[1]
	if not player then
		return false, "The client side's handshake joined no player"
	end

	local bot: any = rig.mock:addBot("Bot")
	server:create(player, rig:at(0, 0))
	server:create(bot, rig:at(0, 4))
	local near: any = server:create(rig.mock:addBot("Near"), rig:at(NEAR, 0))
	local far: any = server:create(rig.mock:addBot("Far"), rig:at(FAR, 0))

	network.View.fire(DISTANCE)
	network.flush()
	rig:deliver()
	rig:tick(TICKS)

	if not Relay.isSent(player, near._slot) then
		return false, `The player whose client sent {DISTANCE} studs was not sent the character at {NEAR}`
	elseif Relay.isSent(player, far._slot) then
		return false, `The player whose client sent {DISTANCE} studs was sent the character at {FAR}`
	elseif not Relay.isSent(bot, near._slot) or not Relay.isSent(bot, far._slot) then
		return false, "The bot, which sent no View, was not sent both characters"
	end

	-- Twice the burst at once, so the rate the settings give refuses some
	for _ = 1, rate.burst * 2 do
		network.View.fire(DISTANCE)
	end

	network.flush()
	rig:deliver()

	if #rig:reportedFor("rate", player) == 0 then
		return false, `{rate.burst * 2} Views at once raised no rate report, at a burst of {rate.burst}`
	end

	return true, nil
end
