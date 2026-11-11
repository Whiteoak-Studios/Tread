--[[
    The dev place's server bootstrap: starts the dev game, and Tread's
    server with it, G7's shot telemetry, the clips' played reports and the
    live panel's runs, then runs each scenario a test or a check asks for
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Clips = require(ServerScriptService.Server.Clips)
local Game = require(ServerScriptService.Server.Game)
local Hits = require(ServerScriptService.Server.Hits)
local Live = require(ServerScriptService.Server.Live)
local Runner = require(ServerScriptService.Server.Runner)

local SCENARIO_ATTRIBUTE: string = "Scenario" -- What a check sets on this script to the name of a scenario to run

-- Hits and Clips are started here, since Game requiring either would close a require cycle through its run. Live
-- starts scenarios as the bridges below do, through the Runner
Game.start()
Hits.start()
Clips.start()
Live.start()

-- Each call is guarded, since a game script may be refused StudioTestService's calls, a live server may lack the
-- service, and outside a test GetTestArgs may refuse
local found: boolean, studioTestService: any = pcall(game.GetService, game, "StudioTestService")
local read: boolean, args: any = false, nil

if found then
	read, args = pcall(studioTestService.GetTestArgs, studioTestService)
end

-- A Play session, or a test Mike starts, names no scenario, and nothing ends it. The Runner ends a test that names one
-- with its verdict, on a thread of its own so the scenario's waits hold nothing else up
if read and type(args) == "table" and type(args.scenario) == "string" then
	task.spawn(Runner.run, args.scenario)
end

-- An execute_luau chunk's require builds fresh copies of every module, which never see the running game, so a check
-- in a Play session asks for a scenario by name on this script, and it runs here in the game's own. Lives as long as
-- the server
script:GetAttributeChangedSignal(SCENARIO_ATTRIBUTE):Connect(function ()
	local name: any = script:GetAttribute(SCENARIO_ATTRIBUTE)
	if type(name) ~= "string" then
		return
	end

	script:SetAttribute(SCENARIO_ATTRIBUTE, nil)
	task.spawn(Runner.run, name)
end)
