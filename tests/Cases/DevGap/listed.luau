--[[
    GapCrossing is a run the live panel lists just after Openings and
    outside Run all, for at least as long as its passes' sprints and settles
    take, and its scenario module gives a scenario's function
--]]

--!strict
local DevServer = require("../../Fixtures/DevServer/Harness")
local DevShared = require("../../Fixtures/DevShared/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local NAME: string = "GapCrossing"
local BEFORE: string = "Openings" -- The run listed just above it
local SCENARIO: string = "dev/Server/Scenarios/GapCrossing.luau"
local NAME_BYTES: number = 32 -- The run event's name, string(1..32) in dev/Schemas/Dev.volt
local SECONDS_A_MINUTE: number = 60
local SETTLES: number = 2 -- A pass settles once its viewer lands and once its target is built

return function (): (boolean, string | nil)
	local loaded: DevServer.Loaded = DevServer.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local config: any = loaded.require(server.Config.GapCrossing)
	local sprint: number = DevShared.load().shared.step.sprint

	-- 1) Listed just after Openings, out of Run all's queue, its name inside the run event's bytes
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

	if listed == nil then
		return false, `The panel doesn't list {NAME}`
	elseif at ~= before + 1 then
		return false, `The panel lists {NAME} at {at}, not just after {BEFORE} at {before}`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}, which needs the real player standing still`
	elseif #NAME > NAME_BYTES then
		return false, `{NAME} is {#NAME} B, past the run event's {NAME_BYTES}`
	end

	-- 2) For at least each pass's two settles and its crossings' sprints from end to end
	local seconds: number = 0
	for _, pass: any in config.passes do
		seconds += SETTLES * config.settle + config.crossings * 2 * pass.reach / sprint
	end

	local minutes: number = seconds / SECONDS_A_MINUTE
	if not (listed.minutes >= minutes) then
		return false, `The panel lists {NAME} as {listed.minutes} minutes, under the {minutes} its passes take`
	end

	-- 3) Its module gives a scenario's function, the dev game, the fleet and the client lines standing in, since only
	-- a run reads them
	local files: { [any]: string } = { [server.Scenarios[NAME]] = SCENARIO }
	local stands: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {}, [server.Bots.ClientLines] = {} }
	local scenario: any = Kit.loader(dataModel, files, stands, loaded.require)(server.Scenarios[NAME])
	if type(scenario) ~= "function" then
		return false, `{NAME}'s module gives a {type(scenario)}, not a scenario's function`
	end

	return true, nil
end
