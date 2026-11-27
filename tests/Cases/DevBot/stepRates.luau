--[[
    The bot harness takes a read's anti-ESP rays over its ticks and its
    workers' busy seconds as milliseconds a second of the read, for the step
    table alone, leaving out one with no divisor or no figure
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"

-- Each read's ticks, relay ticks skipped, seconds, rays and workers' busy seconds, each a power of two's share so the
-- quotients are exact
local READS: { { [string]: number } } = {
	-- 3,000 rays over 20 ticks, and 0.0078125 s busy over 0.5 s
	{ ticks = 20, relaySkipped = 0, seconds = 0.5, antiEspRays = 3000, antiEspWorkerBusy = 0.0078125 },

	-- Every tick dropped: no rays a tick, and 0.001953125 s busy over 0.25 s
	{ ticks = 0, relaySkipped = 0, seconds = 0.25, antiEspRays = 40, antiEspWorkerBusy = 0.001953125 },

	-- No time since the last read: rays a tick alone
	{ ticks = 10, relaySkipped = 0, seconds = 0, antiEspRays = 500, antiEspWorkerBusy = 0.003 },

	-- A server that made no anti-ESP workers reads no busy time, and the relay ticks skipped never touch the rays
	{ ticks = 16, relaySkipped = 2, seconds = 1, antiEspRays = 800 },
}

-- Worked by hand: 3000 / 20, 500 / 10 and 800 / 16 rays a tick, and 0.0078125 / 0.5 and 0.001953125 / 0.25 s a second
-- in milliseconds
local EXPECTED: { [string]: string } = {
	antiEspRays = "150,50,50",
	antiEspWorkerBusy = "15.625,7.8125",
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	local samples: { [string]: { number } } = {}
	for _, read: { [string]: number } in READS do
		Run.counts(read, samples)
	end

	for name: string, expected: string in EXPECTED do
		local got: string = table.concat(samples[name] or {}, ",")
		if got ~= expected then
			return false, `{name} read as {got} over the reads, not {expected}`
		end
	end

	-- Nothing else, since none of the reads carries a configured count
	for name: string in samples do
		if EXPECTED[name] == nil then
			return false, `The reads gave {name} too, which none of them carries`
		end
	end

	return true, nil
end
