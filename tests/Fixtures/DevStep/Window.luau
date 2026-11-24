--[[
    A bot run's window as its cases take it: four frames, eight Heartbeats
    over two ticks with each place in the tick filled, two reads of stats,
    counts, caps and two relay clocks, and a run with the bot harness's Run
--]]

--!strict
local Harness = require("../DevServer/Harness")
local Kit = require("../Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"

local Window = {}

--[[
    A fresh window, since its lines sort its lists in place: 4 frames over
    62.5 ms, Heartbeats placed 1, 2, 3, 1, 2, 3, 4 and 4 in their ticks,
    two rounds each released by the next Heartbeat and one Heartbeat lost,
    with the bots' stage 1 ms in each tick's own Heartbeat
--]]

function Window.taken(): any
	return {
		sampled = {
			frames = { 16, 17, 20, 18 },
			heartbeatTimes = { 0.004, 0.005, 0.006, 0.007 },
			physicsTimes = { 0.001, 0.002, 0.003, 0.004 },
			dataSend = { 3.5, 3.75 },
		},

		elapsed = 0.0625,

		-- Ticked and held, then released, then none, twice, then two with none; seconds of the whole loop's work
		readout = {
			times = { 0.004, 0.002, 0.001, 0.006, 0.003, 0.0005, 0.00025, 0.00025 },
			flags = { 3, 12, 0, 3, 12, 0, 0, 0 },
			bots = { 0.001, 0, 0, 0.001, 0, 0, 0, 0 },
			through = 8,
			lost = 1,
		},

		totals = { 4, 6 },
		finishes = { 1.5, 2.5 },
		roundsDropped = 0,

		samples = {
			viewerBytes = { 1000, 3000 },
			ticks = { 20, 20 },
			dropped = { 0, 1 },
			relaySkipped = { 2, 0 },
			ownerChecked = { 40, 38 },
			ownerMismatches = { 1, 2 },
			antiEspHidden = { 10, 30 },
			antiEspFailOpens = { 0, 1 },
			antiEspWorkerTests = { 400, 500 },
			antiEspWorkerLongest = { 0.002, 0.004 }, -- Seconds
			antiEspLateBatches = { 0, 2 },
			crowdRest = { 27, 45 },
			antiEspCut = { 1, 2 },
			npcsWaited = { 10, 0 },
			relayLeft = { 0, 6 },
			relayOver = { 0, 4 },
			farHalved = { 2, 0 },
			relaySend = { 0.0365, 0.02 }, -- Seconds, each read's smoothed level
			decodeMs = { 0.25, 0.75 },
			simulateMs = { 1, 2 },
			npcsMs = { 0, 0 },
			historyMs = { 0.125, 0.25 },
			relayMs = { 1.5, 2.5 },
			antiEspMs = { 0.5, 1 },
			antiEspP95Ms = { 0.625, 0.875 },
			["clock headMs"] = { 0.25, 0.5 },
			["clock backMs"] = { 1, 2 },
		},

		rates = {
			recordsSent = { 100, 140 },
			recordsCut = { 0, 2 },
			bytesOut = { 2000, 2400 },
			antiEspTests = { 50, 70 },
			antiEspRays = { 900, 1100 },
			antiEspWorkerBusy = { 12.5, 16 }, -- Milliseconds a second
			crowdRest = { 1.5, 2.25 }, -- The samples' 27 and 45 over the reads' 18 and 20 relay runs
		},

		skipped = 120,
	}
end

-- The bot harness's Run over stand-ins for the dev game and its fleet, whose real modules start the dev game's server
function Window.run(): any
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }

	return Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)
end

return Window
