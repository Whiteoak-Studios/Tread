--[[
    A player's first sample sets its round trip to the engine's ping with no
    jitter, the round trip holds whatever the engine says until the next
    sample, and that sample's jitter is the two pings' weighted spread
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")

local CONNECTIONS: string = "src/Server/Connections.luau"
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing
local INTERVAL: number = 0.5 -- Seconds between the two samples
local FIRST_PING: number = 0.08 -- Seconds
local SECOND_PING: number = 0.2
local CLOSE: number = 1e-12 -- How near each value must be to the one the weights give

return function (): (boolean, string | nil)
	local Connections: any = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, nil)

	local player: any = roblox.Instance.new("Player")
	local connection: any = Connections.add(player)

	Pings[player] = FIRST_PING
	connection:sample(INTERVAL)

	if connection:rtt() ~= FIRST_PING then
		return false, `The first sample set the round trip to {connection:rtt()}, not the ping {FIRST_PING}`
	elseif connection:jitter() ~= 0 then
		return false, `One sample gave jitter {connection:jitter()}, not 0`
	end

	Pings[player] = SECOND_PING
	if connection:rtt() ~= FIRST_PING then
		return false, `With no new sample the round trip moved to {connection:rtt()}, the engine's ping now`
	end

	-- Two pings, weighted 1 - w and w, lie w and 1 - w of their gap from their mean
	connection:sample(INTERVAL)

	local weight: number = 1 - math.exp(-INTERVAL / SMOOTHING)
	local gap: number = SECOND_PING - FIRST_PING
	local mean: number = FIRST_PING + weight * gap
	local spread: number = gap * math.sqrt(weight * (1 - weight))

	if math.abs(connection:rtt() - mean) > CLOSE then
		return false, `The second sample set the round trip to {connection:rtt()}, not their weighted mean {mean}`
	elseif math.abs(connection:jitter() - spread) > CLOSE then
		return false, `The second sample gave jitter {connection:jitter()}, not their weighted spread {spread}`
	end

	return true, nil
end
