--[[
    The dev place's server bootstrap: starts the dev game with Tread's
    server, G7's shot telemetry, the clips' played reports, the live panel,
    the bot panel, the split's switch, the ghosts, then each scenario asked for
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tread = require(ReplicatedStorage.Packages.Tread)

local Tick = require(ReplicatedStorage.Packages.Tread.Server.Tick)

local BotPanel = require(ServerScriptService.Server.BotPanel)
local Clips = require(ServerScriptService.Server.Clips)
local Game = require(ServerScriptService.Server.Game)
local Ghost = require(ServerScriptService.Server.Ghost)
local Hits = require(ServerScriptService.Server.Hits)
local Live = require(ServerScriptService.Server.Live)
local Run = require(ServerScriptService.Server.Bots.Run)
local Runner = require(ServerScriptService.Server.Runner)
local Split = require(ServerScriptService.Server.Split)

local SCENARIO_ATTRIBUTE: string = "Scenario" -- What a check sets on this script to the name of a scenario to run

-- Hits and Clips are started here, since Game requiring either would close a require cycle through its run. Live
-- starts scenarios as the bridges below do, through the Runner
Game.start()
Hits.start()
Clips.start()
Live.start()
BotPanel.start(Live.running)
Split.start(Live.running)

-- The ghosts' label is the state a viewer's ghosts are read under, the split's as the tick loop has it and the relay
-- workers the server started, so a viewer's means start again only on a flip
local server: Tread.Server = Game.get()
Ghost.start(server, function (): string
	return Split.label(Tick.splitOn(), Run.workers())
end, Live.running)

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
