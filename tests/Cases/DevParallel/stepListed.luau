--[[
    ParallelStep is a scenario the panel lists after ParallelFrames and
    outside Run all, for as long as its waits can take, saved under its
    start and its name, with its config block whole and in range
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local NAME: string = "ParallelStep"
local BEFORE: string = "ParallelFrames" -- The run listed just above it
local LIVE: string = "dev/Server/Live.luau"
local SCENARIO: string = "dev/Server/Scenarios/ParallelStep.luau"
local STEP: string = "dev/Server/Parallel/Step.luau"
local STARTED: number = 1763900000 -- The os.time() a stand-in run started at
local SECONDS_A_MINUTE: number = 60
local BYTES_PER_KILOBYTE: number = 1000
local SEED_LIMIT: number = 4294967295 -- 2^32 - 1, the highest seed the queries' generator takes

-- The waits for answers a run makes: P9's check, P2's casts, P7's two arms and P3's battery
local WAITS: number = 5

-- The config block's counts, each a whole number above 0, and its seeds, each a whole number from 1 to SEED_LIMIT
local COUNTS: { string } = { "workers", "slots", "boxes", "pieceBytes" }
local SEEDS: { string } = { "slotSeed", "planSeed", "boxSeed" }

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local parallel: any = loaded.require(server.Config.Parallel)
	local step: any = parallel.step

	-- 1) The config block, its counts whole, its seeds in the generator's range, its sphere and wait above 0, and its
	-- pieces no larger than P5's largest return, which a live server has already carried
	if type(step) ~= "table" then
		return false, "The parallel config has no step block"
	end

	for _, key: string in COUNTS do
		if type(step[key]) ~= "number" or not (step[key] >= 1) or step[key] % 1 ~= 0 then
			return false, `The step block's {key} is {step[key]}`
		end
	end

	for _, key: string in SEEDS do
		local seed: any = step[key]
		if type(seed) ~= "number" or not (seed >= 1 and seed <= SEED_LIMIT) or seed % 1 ~= 0 then
			return false, `The step block's {key} is {seed}`
		end
	end

	for _, key: string in { "smallRadius", "answerWait" } do
		if type(step[key]) ~= "number" or not (step[key] > 0) then
			return false, `The step block's {key} is {step[key]}`
		end
	end

	local largest: number = 0
	for _, kilobytes: number in parallel.returns.returnKilobytes do
		largest = math.max(largest, kilobytes * BYTES_PER_KILOBYTE)
	end

	if step.pieceBytes > largest then
		return false, `The step block's pieces are {step.pieceBytes} B, past P5's largest return of {largest} B`
	end

	-- 2) Listed just after ParallelFrames, out of Run all's queue, for at least the pool's ready wait and every wait
	-- for answers run out
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

	local minutes: number = (parallel.readyWait + WAITS * step.answerWait) / SECONDS_A_MINUTE

	if listed == nil then
		return false, `The panel doesn't list {NAME}`
	elseif at ~= before + 1 then
		return false, `The panel lists {NAME} at {at}, not just after {BEFORE} at {before}`
	elseif not (listed.minutes >= minutes) then
		return false, `The panel lists {NAME} as {listed.minutes} minutes, under the {minutes} its waits can take`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}`
	end

	-- 3) Its scenario module gives a scenario's function, the dev shared table standing in since only a run reads it
	local files: { [any]: string } = { [server.Scenarios[NAME]] = SCENARIO, [server.Parallel.Step] = STEP }
	local stands: { [any]: any } = { [shared.Dev.Config] = {} }
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
