--[[
    Pings that swing a fixed amount either side of a middle at every sample,
    one interval apart, give what the weights give such an endless series:
    jitter 2d√(1 - w)/(2 - w) for a swing of d and a weight of w a sample,
    and a round trip w/(2 - w) of the swing past the middle, on its side
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")

local CONNECTIONS: string = "src/Server/Connections.luau"
local SMOOTHING: number = 1 -- Seconds, the server settings' rewind.rttSmoothing
local INTERVAL: number = 0.25 -- Seconds between samples
local MIDDLE: number = 0.2 -- Seconds the pings swing about
local SWING: number = 0.1 -- How far either side, so the pings are 0.1 and 0.3

-- Enough that the first ping's weight, standing in for the series before it, is e^-49.75 of the whole
local SAMPLES: number = 200
local CLOSE: number = 1e-12 -- How near each value must be to the one the weights give

return function (): (boolean, string | nil)
	local Connections: any = Environment.load(CONNECTIONS)
	Connections.start(SMOOTHING, nil)

	local player: any = roblox.Instance.new("Player")
	local connection: any = Connections.add(player)

	local weight: number = 1 - math.exp(-INTERVAL / SMOOTHING)
	local jitter: number = 2 * SWING * math.sqrt(1 - weight) / (2 - weight)
	local lean: number = SWING * weight / (2 - weight) -- How far the round trip sits past the middle

	-- The low ping first, so an even count of samples ends on the high one; then one more ends on the low one
	for count: number = 1, SAMPLES + 1 do
		local side: number = count % 2 == 0 and 1 or -1
		Pings[player] = MIDDLE + side * SWING
		connection:sample(INTERVAL)

		if count >= SAMPLES then
			local rtt: number = connection:rtt()
			local wanted: number = MIDDLE + side * lean

			if math.abs(connection:jitter() - jitter) > CLOSE then
				return false, `After {count} samples the jitter is {connection:jitter()}, not {jitter}`
			elseif math.abs(rtt - wanted) > CLOSE then
				return false, `After {count} samples the round trip is {rtt}, not {wanted}`
			end
		end
	end

	return true, nil
end
