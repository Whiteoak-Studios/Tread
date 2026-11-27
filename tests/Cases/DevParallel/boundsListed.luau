--[[
    ParallelBounds is a scenario the panel lists after ParallelStep and
    outside Run all, for as long as its loads and waits can take, saved
    under its start and its name, with its config block whole and in range
--]]

--!strict
local DevShared = require("../../Fixtures/DevShared/Harness")
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local NAME: string = "ParallelBounds"
local BEFORE: string = "ParallelStep" -- The run listed just above it
local LIVE: string = "dev/Server/Live.luau"
local SCENARIO: string = "dev/Server/Scenarios/ParallelBounds.luau"
local BOUNDS: string = "dev/Server/Parallel/Bounds.luau"
local SETTLES: string = "dev/Server/Parallel/Settles.luau"
local STARTED: number = 1763900000 -- The os.time() a stand-in run started at
local SECONDS_A_MINUTE: number = 60

-- Seconds a load's calibration, build and removal take beside its warm-up and window, the most the panel's other
-- single-seed loads of 150 players allow: BenchWorkers' 11 minutes for four runs of a 30 s warm-up and 120 s
local BUILD: number = 15

-- Why a timing is no bot harness Timing, nil for one that is: seeds whole numbers, a warm-up from 0, the rest above 0
local function refusal(timing: any): string?
	if type(timing) ~= "table" or type(timing.seeds) ~= "table" or #timing.seeds == 0 then
		return "has no seeds"
	end

	for _, seed: any in timing.seeds do
		if type(seed) ~= "number" or seed % 1 ~= 0 then
			return `seeds {seed}`
		end
	end

	if type(timing.warmup) ~= "number" or not (timing.warmup >= 0) then
		return `warms up {timing.warmup} s`
	end

	for _, key: string in { "window", "interval" } do
		if type(timing[key]) ~= "number" or not (timing[key] > 0) then
			return `has a {key} of {timing[key]} s`
		end
	end

	return nil
end

-- The bots a scenario's groups build, NPCs and sleepers aside, since the sampler reads the fleet's bots alone
local function bots(scenario: any): number
	local count: number = 0
	for _, group: any in scenario.groups do
		if group.kind == nil then
			count += group.count
		end
	end

	return count
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local parallel: any = loaded.require(server.Config.Parallel)
	local scenarios: any = loaded.require(server.Bots.Config).scenarios
	local rate: number = DevShared.load().shared.rates.simulation
	local bounds: any = parallel.bounds

	-- 1) The config block: loads the bot harness has, a Timing, a cap no load's window can pass, and clone boxes
	-- that are a whole number from 1 to the cap
	if type(bounds) ~= "table" then
		return false, "The parallel config has no bounds block"
	elseif type(bounds.loads) ~= "table" or #bounds.loads == 0 then
		return false, "The bounds block names no load"
	end

	local timing: any = bounds.timing
	local refused: string? = refusal(timing)
	if refused then
		return false, `The bounds block's timing {refused}`
	end

	local most: number = 0
	for _, load: any in bounds.loads do
		local scenario: any = nil
		if type(load) == "string" then
			scenario = scenarios[load]
		end

		if scenario == nil then
			return false, `The bounds block's load {load} is no scenario the bot harness has`
		end

		most = math.max(most, bots(scenario))
	end

	-- One box at most a bot a tick, through every seed's window, since the sampler runs on across them
	local boxes: number = most * rate * timing.window * #timing.seeds
	local cap: any = bounds.cap
	if type(cap) ~= "number" or cap % 1 ~= 0 or not (cap >= boxes) then
		return false, `The bounds block's cap is {cap}, under the {boxes} boxes {most} bots can give at {rate} Hz`
	end

	local sent: any = bounds.parallelBoxes
	if type(sent) ~= "number" or sent % 1 ~= 0 or not (sent >= 1 and sent <= cap) then
		return false, `The bounds block's parallelBoxes is {sent}, outside 1 to its cap of {cap}`
	end

	-- 2) Listed just after ParallelStep, out of Run all's queue, for at least every load's run with its calibration
	-- and build, the pool's ready wait and the clones' wait for answers
	local listed: any = nil
	local at: number = 0
	local before: number = 0
	for index: number, run: any in LiveRuns.runs do
		if run.name == NAME then
			listed = run
			at = index
		elseif run.name == BEFORE then
			before = index
		end
	end

	local seconds: number = parallel.readyWait + parallel.step.answerWait
	for _ in bounds.loads do
		seconds += #timing.seeds * (timing.warmup + timing.window + BUILD)
	end

	local minutes: number = seconds / SECONDS_A_MINUTE

	if listed == nil then
		return false, `The panel doesn't list {NAME}`
	elseif at ~= before + 1 then
		return false, `The panel lists {NAME} at {at}, not just after {BEFORE} at {before}`
	elseif not (listed.minutes >= minutes) then
		return false, `The panel lists {NAME} as {listed.minutes} minutes, under the {minutes} its loads and waits take`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}`
	end

	-- 3) Its scenario module gives a scenario's function, the dev shared table and the bot harness's run standing in
	-- since only a run reads them
	local files: { [any]: string } = {
		[server.Scenarios[NAME]] = SCENARIO,
		[server.Parallel.Bounds] = BOUNDS,
		[server.Parallel.Settles] = SETTLES,
	}

	local stands: { [any]: any } = { [shared.Dev.Config] = {}, [server.Bots.Run] = {} }
	local scenario: any = Kit.loader(dataModel, files, stands, loaded.require)(server.Scenarios[NAME])
	if type(scenario) ~= "function" then
		return false, `{NAME}'s module gives a {type(scenario)}, not a scenario's function`
	end

	-- 4) Saved as a single run under its start and its name, through a game whose DataStoreService keeps each key
	local written: { string } = {}
	local opened: { string } = {}
	local store: any = {
		GetDataStore = function (_: any, name: string): any
			table.insert(opened, name)

			return {
				SetAsync = function (_: any, key: string, _: any)
					table.insert(written, key)
				end,
			}
		end,
	}

	local place: any = {
		GetService = function (_: any, name: string): any
			if name == "DataStoreService" then
				return store
			end

			return dataModel:GetService(name)
		end,
	}

	local results: { [any]: any } = {
		[shared.Network.Server] = {},
		[server.BotPanel] = {},
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(place, { [server.Live] = LIVE }, results, loaded.require)(server.Live)
	Live.saveRun(STARTED, NAME, `{NAME}'s report`)

	if table.concat(written, ",") ~= `{STARTED}-{NAME}` or table.concat(opened, ",") ~= "LiveRuns" then
		return false, `{NAME}'s report was written under {table.concat(written, ",")} in {table.concat(opened, ",")}`
	end

	return true, nil
end
