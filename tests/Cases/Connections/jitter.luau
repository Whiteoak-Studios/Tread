--[[
    A player's jitter is the weighted standard deviation of the pings it
    sampled, 0 before any and for a steady ping, and a bot's, whose round
    trip is the fixed bots.rtt, is 0
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")

local CONNECTIONS: string = "src/Server/Connections.luau"
local BOT_RTT: number = 0.25 -- Seconds, the server settings' bots.rtt
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing
local INTERVAL: number = math.log(2) -- Seconds between samples, which weighs each new ping a half
local STEADY: number = 0.08 -- Seconds, a ping that never moves
local STEADY_SAMPLES: number = 10
local CLOSE: number = 1e-12 -- How near a jitter must be to the one its samples give

-- Pings in seconds, and their weighted mean and standard deviation: the last weighs a half, the one before it a
-- quarter and the first two an eighth each, so their mean is 0.3125
local PINGS: { number } = { 0.1, 0.2, 0.3, 0.4 }
local MEAN: number = 0.3125
local SPREAD: number = math.sqrt(0.125 * 0.2125 ^ 2 + 0.125 * 0.1125 ^ 2 + 0.25 * 0.0125 ^ 2 + 0.5 * 0.0875 ^ 2)

return function (): (boolean, string | nil)
	local Connections: any = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, { rtt = BOT_RTT })

	local moving: any = roblox.Instance.new("Player")
	local steady: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }

	local movingConnection: any = Connections.add(moving)
	local steadyConnection: any = Connections.add(steady)
	local botConnection: any = Connections.add(bot)

	if movingConnection:jitter() ~= 0 then
		return false, `A connection that sampled nothing has jitter {movingConnection:jitter()}`
	end

	for _, ping: number in PINGS do
		Pings[moving] = ping
		movingConnection:sample(INTERVAL)
	end

	local jitter: number = movingConnection:jitter()
	if math.abs(jitter - SPREAD) > CLOSE then
		return false, `Pings of 0.1, 0.2, 0.3 and 0.4 s gave jitter {jitter}, not their weighted deviation {SPREAD}`
	elseif math.abs(movingConnection:rtt() - MEAN) > CLOSE then
		return false, `The round trip reads {movingConnection:rtt()}, not the pings' weighted mean, {MEAN}`
	end

	Pings[steady] = STEADY
	for _ = 1, STEADY_SAMPLES do
		steadyConnection:sample(INTERVAL)
	end

	if steadyConnection:jitter() ~= 0 then
		return false, `A ping of {STEADY} s every sample gave jitter {steadyConnection:jitter()}, not 0`
	end

	for _ = 1, STEADY_SAMPLES do
		botConnection:sample(INTERVAL)
	end

	if botConnection:jitter() ~= 0 or botConnection:rtt() ~= BOT_RTT then
		return false, `A bot's round trip is {botConnection:rtt()} with jitter {botConnection:jitter()}`
	end

	return true, nil
end
