--[[
    ParallelFrames is a scenario the panel lists after ParallelReturn and
    outside Run all, for as long as its arms take by arithmetic, saved
    under its start and its name, with its config block whole
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local NAME: string = "ParallelFrames"
local BEFORE: string = "ParallelReturn" -- The run listed just above it
local LIVE: string = "dev/Server/Live.luau"
local STARTED: number = 1763900000 -- The os.time() a stand-in run started at
local HEARTBEATS: number = 60 -- A live server's Heartbeats a second
local SECONDS_A_MINUTE: number = 60

-- A worker arm's round takes at most two frames when it lands by the next frame's Heartbeat, the next one handed out
-- at the frame after, and a baseline's lands in its own frame
local WORKER_FRAMES: number = 2
local BASELINE_FRAMES: number = 1

-- The config block's keys, each a number above 0, and the list of spins
local KEYS: { string } = { "workers", "rounds", "armedWait", "roundWait", "armWait" }

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local Frames: any = loaded.require(server.Parallel.Frames)
	local frames: any = loaded.require(server.Config.Parallel).frames

	-- 1) The config block, every value a number above 0 and every worker count whole
	if type(frames) ~= "table" then
		return false, "The parallel config has no frames block"
	end

	for _, key: string in KEYS do
		if type(frames[key]) ~= "number" or not (frames[key] > 0) then
			return false, `The frames block's {key} is {frames[key]}`
		end
	end

	if frames.workers % 1 ~= 0 or frames.rounds % 1 ~= 0 or #frames.spinsMs == 0 then
		return false,
			`The frames block gives {frames.workers} workers, {frames.rounds} rounds and {#frames.spinsMs} spins`
	end

	for _, spin: any in frames.spinsMs do
		if type(spin) ~= "number" or not (spin > 0) then
			return false, `The frames block spins a round {spin} ms`
		end
	end

	-- 2) Listed just after ParallelReturn, out of Run all's queue, for at least what its arms' rounds take
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

	local frameCount: number = 0
	for _, arm: any in Frames.arms() do
		local each: number = arm.wake == "none" and BASELINE_FRAMES or WORKER_FRAMES
		frameCount += each * frames.rounds
	end

	local minutes: number = frameCount / HEARTBEATS / SECONDS_A_MINUTE

	if listed == nil then
		return false, `The panel doesn't list {NAME}`
	elseif at ~= before + 1 then
		return false, `The panel lists {NAME} at {at}, not just after {BEFORE} at {before}`
	elseif not (listed.minutes >= minutes) then
		return false, `The panel lists {NAME} as {listed.minutes} minutes, under the {minutes} its arms' rounds take`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}`
	end

	-- 3) Its scenario module gives a scenario's function
	local scenario: any = loaded.require(server.Scenarios[NAME])
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
