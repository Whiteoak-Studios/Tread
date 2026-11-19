--[[
    After a step in the engine's ping, the round trip closes on the new ping
    at the rate the smoothing's time constant gives: 1/e of the step is
    left after one time constant and 1/e² after two, however the samples
    split the time, and a shorter time constant closes it faster
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")

local CONNECTIONS: string = "src/Server/Connections.luau"
local FROM: number = 0.05 -- Seconds, the ping before the step
local TO: number = 0.25 -- And after it
local FIRST: number = 0.1 -- Seconds the first sample is handed, which it never weighs
local CLOSE: number = 1e-12 -- How near the round trip must be to the one the time constant gives

-- A smoothing time constant in seconds, and the seconds between each sample after the step
type Trial = { label: string, smoothing: number, intervals: { number } }

-- Ten samples a tenth of a second apart, and twenty
local TENTHS: { number } = table.create(10, 0.1)
local TWENTY_TENTHS: { number } = table.create(20, 0.1)

local TRIALS: { Trial } = {
	{ label = "one time constant in tenths", smoothing = 1, intervals = TENTHS },
	{ label = "two time constants in tenths", smoothing = 1, intervals = TWENTY_TENTHS },
	{ label = "one time constant in uneven steps", smoothing = 1, intervals = { 0.05, 0.3, 0.15, 0.5 } },
	{ label = "two of a time constant half as long", smoothing = 0.5, intervals = TENTHS },
}

return function (): (boolean, string | nil)
	for _, trial: Trial in TRIALS do
		local Connections: any = Environment.load(CONNECTIONS)
		Connections.start(trial.smoothing, nil)

		local player: any = roblox.Instance.new("Player")
		local connection: any = Connections.add(player)

		Pings[player] = FROM
		connection:sample(FIRST)
		Pings[player] = TO

		local elapsed: number = 0
		for _, seconds: number in trial.intervals do
			connection:sample(seconds)
			elapsed += seconds
		end

		local expected: number = TO + (FROM - TO) * math.exp(-elapsed / trial.smoothing)
		local rtt: number = connection:rtt()
		if math.abs(rtt - expected) > CLOSE then
			return false, `After {trial.label} the round trip reads {rtt}, not {expected}`
		end
	end

	return true, nil
end
