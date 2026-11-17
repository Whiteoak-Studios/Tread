--[[
    The bot harness takes a read's relay counts over its relay runs, its
    ticks less the relay ticks it skipped, and anti-ESP's tests over its
    ticks, leaving out a figure whose divisor is none
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"

-- Each read's ticks, relay ticks skipped and counts
local READS: { { [string]: number } } = {
	-- 20 ticks less 4 skipped: 16 relay runs
	{ ticks = 20, relaySkipped = 4, recordsSent = 3200, recordsCut = 160, bytesOut = 64000, antiEspTests = 1000 },

	-- More skipped than run, as a short read charged with the last one's: no relay runs, so only the tests count
	{ ticks = 2, relaySkipped = 3, recordsSent = 10, recordsCut = 1, bytesOut = 100, antiEspTests = 40 },

	-- Every tick's relay skipped: no relay runs
	{ ticks = 3, relaySkipped = 3, recordsSent = 10, recordsCut = 1, bytesOut = 100, antiEspTests = 9 },

	-- Every tick dropped: nothing counts
	{ ticks = 0, relaySkipped = 0, recordsSent = 5, recordsCut = 1, bytesOut = 50, antiEspTests = 7 },
}

-- Each figure's samples over the reads: the relay counts over 16 runs from the first alone, the tests over its ticks
local EXPECTED: { [string]: string } = {
	recordsSent = "200",
	recordsCut = "10",
	bytesOut = "4000",
	antiEspTests = "50,20,3",
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

	return true, nil
end
