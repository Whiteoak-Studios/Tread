--[[
    A player's connection reads the engine's ping each time before it
    samples one and a bot's reports bots.rtt, each found by its player or
    bot until removed, and a player added again gets a new one
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")

local CONNECTIONS: string = "src/Server/Connections.luau"
local BOT_RTT: number = 0.25 -- Seconds, the server settings' bots.rtt
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing
local FIRST_PING: number = 0.08 -- Seconds, what the engine reports for the player
local LATER_PING: number = 0.12

return function (): (boolean, string | nil)
	local Connections: any = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, { rtt = BOT_RTT })

	local player: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }
	Pings[player] = FIRST_PING

	local playerConnection: any = Connections.add(player)
	local botConnection: any = Connections.add(bot)

	if playerConnection.player ~= player or botConnection.player ~= bot then
		return false, "A connection names someone other than whose it is"
	elseif playerConnection:rtt() ~= FIRST_PING then
		return false, `The player's round trip is {playerConnection:rtt()}, not the engine's {FIRST_PING}`
	elseif botConnection:rtt() ~= BOT_RTT then
		return false, `The bot's round trip is {botConnection:rtt()}, not bots.rtt's {BOT_RTT}`
	end

	Pings[player] = LATER_PING
	if playerConnection:rtt() ~= LATER_PING then
		return false, `With the engine's ping at {LATER_PING} the round trip reads {playerConnection:rtt()}`
	end

	if Connections.get(player) ~= playerConnection or Connections.get(bot) ~= botConnection then
		return false, "A player or bot found a connection other than its own"
	elseif Connections.get({ Name = "Nobody" }) ~= nil then
		return false, "A bot with no connection found one"
	end

	Connections.remove(player)
	if Connections.get(player) ~= nil then
		return false, "A removed player still has a connection"
	elseif Connections.get(bot) ~= botConnection then
		return false, "Removing the player removed the bot's connection too"
	end

	local again: any = Connections.add(player)
	if again == playerConnection or Connections.get(player) ~= again then
		return false, "A player added again did not get a connection of its own"
	end

	return true, nil
end
