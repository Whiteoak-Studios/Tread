--[[
    Connections.start refuses a smoothing time that is no finite number
    above 0 and stays unstarted, and a player's or a bot's sample refuses
    seconds that are not, changing nothing
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")
local Refuses = require("../../Fixtures/Codec/Refuses")

local CONNECTIONS: string = "src/Server/Connections.luau"
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing
local BOT_RTT: number = 0.25 -- Seconds, the server settings' bots.rtt
local INTERVAL: number = 0.5 -- Seconds, a sample's honest interval
local FIRST_PING: number = 0.08 -- Seconds
local LATER_PING: number = 0.3

-- Values refused as a smoothing time or a sample's seconds, each by what it gets wrong
local BAD: { [string]: any } = {
	["0"] = 0,
	["a negative time"] = -1,
	["NaN"] = 0 / 0,
	["an infinity"] = math.huge,
	["no number"] = "1",
}

return function (): (boolean, string | nil)
	for problem: string, value: any in BAD do
		local Connections: any = Environment.load(CONNECTIONS)
		local refused: boolean, why: string =
			Refuses("rewind.rttSmoothing in seconds above 0", Connections.start, value)
		if not refused then
			return false, `A smoothing time of {problem} started: {why}`
		end

		-- A refused start leaves it unstarted, so a good one still runs
		local started: boolean, failure: any = pcall(Connections.start, SMOOTHING, nil)
		if not started then
			return false, `After a smoothing time of {problem} was refused, a good start failed: {failure}`
		end
	end

	local unset: boolean, why: string =
		Refuses("rewind.rttSmoothing in seconds above 0", Environment.load(CONNECTIONS).start)
	if not unset then
		return false, `No smoothing time started: {why}`
	end

	local Connections: any = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, { rtt = BOT_RTT })

	local player: any = roblox.Instance.new("Player")
	local connection: any = Connections.add(player)
	local bot: any = Connections.add({ Name = "Bot" })

	Pings[player] = FIRST_PING
	connection:sample(INTERVAL)
	Pings[player] = LATER_PING

	for problem: string, value: any in BAD do
		local refused: boolean, reason: string = Refuses("above 0 and finite", connection.sample, connection, value)
		if not refused then
			return false, `A player's sample took {problem}: {reason}`
		end

		refused, reason = Refuses("above 0 and finite", bot.sample, bot, value)
		if not refused then
			return false, `A bot's sample took {problem}: {reason}`
		end
	end

	if connection:rtt() ~= FIRST_PING or connection:jitter() ~= 0 then
		return false, `Refused samples moved the round trip to {connection:rtt()} with jitter {connection:jitter()}`
	end

	return true, nil
end
