--[[
    Connections refuses an add before start, a second start, bots without
    a usable rtt, a bot with no bots.rtt, anything but a Player or a bot,
    a second connection for one, and removing one that has none
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local CONNECTIONS: string = "src/Server/Connections.luau"
local BOT_RTT: number = 0.25 -- Seconds, the server settings' bots.rtt
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing

-- bots tables start refuses, each with what it gets wrong
local BAD_BOTS: { [string]: any } = {
	["a round trip of 0"] = { rtt = 0 },
	["a negative round trip"] = { rtt = -1 },
	["a NaN round trip"] = { rtt = 0 / 0 },
	["an infinite round trip"] = { rtt = math.huge },
	["a round trip that is no number"] = { rtt = "fast" },
	["no table"] = 0.25,
}

return function (): (boolean, string | nil)
	local bot: { Name: string } = { Name = "Bot" }

	local Connections: any = Environment.load(CONNECTIONS)
	local refused: boolean, why: string = Refuses("before Connections.start", Connections.add, bot)
	if not refused then
		return false, `A connection was added before start: {why}`
	end

	for problem: string, bots: any in BAD_BOTS do
		refused, why = Refuses("rtt in seconds above 0", Environment.load(CONNECTIONS).start, SMOOTHING, bots)
		if not refused then
			return false, `Bots with {problem} started: {why}`
		end
	end

	-- A server whose settings give no bots.rtt takes players and no bot
	Connections.start(SMOOTHING, nil)
	refused, why = Refuses("needs a server whose settings give bots.rtt", Connections.add, bot)
	if not refused then
		return false, `A bot was added on a server with no bots.rtt: {why}`
	end

	refused, why = Refuses("runs once", Connections.start, { rtt = BOT_RTT })
	if not refused then
		return false, `Connections started twice: {why}`
	end

	Connections = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, { rtt = BOT_RTT })

	refused, why = Refuses("takes a Player or a bot", Connections.add, roblox.Instance.new("Folder"))
	if not refused then
		return false, `A Folder was given a connection: {why}`
	end

	refused, why = Refuses("takes a Player or a bot", Connections.add, 42)
	if not refused then
		return false, `A number was given a connection: {why}`
	end

	Connections.add(bot)
	refused, why = Refuses("already has a connection", Connections.add, bot)
	if not refused then
		return false, `A bot was given a second connection: {why}`
	end

	refused, why = Refuses("has none", Connections.remove, { Name = "Nobody" })
	if not refused then
		return false, `A bot with no connection was removed: {why}`
	end

	return true, nil
end
