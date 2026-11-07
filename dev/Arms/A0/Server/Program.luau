--[[
    The arm's runs by scenario and seed: one started from execute_luau in
    Studio, or every configured run in turn once a live server has a player
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Bots = require(ServerScriptService.Arm.Bots)
local Config = require(ReplicatedStorage.Arm.Config)
local Run = require(ServerScriptService.Arm.Run)

local ARM: string = Config.arm
local LIVE_JOIN_TIMEOUT: number = Config.liveJoinTimeout
local LIVE_START_DELAY: number = Config.liveStartDelay
local PAUSE_SECONDS: number = Config.pauseSeconds
local POLL_INTERVAL: number = Config.pollInterval

local Types = require(ReplicatedStorage.Arm.Types)

type Load = Types.Load
type Scenario = Types.Scenario

local Program = {}

--[[
    A run's label, and the load that starts its scenario for its seed, or
    nil when no scenario has the name or the seed is not a number
--]]

local function resolve(scenario: string, seed: number): (string, Load?)
	local label: string = `{ARM} {scenario} seed {seed}`

	local found: Scenario? = Config.scenarios[scenario]
	if not found or type(seed) ~= "number" then
		return label, nil
	end

	local spec: Scenario = found
	return label, function ()
		return Bots.start(spec, seed)
	end
end

--[[
    Starts one run and answers at once, for an execute_luau chunk:
    Program.start("S2", 1) returns true and when its line will be ready,
    or false and why it was refused
--]]

function Program.start(scenario: string, seed: number): (boolean, string)
	local label: string, load: Load? = resolve(scenario, seed)
	if not load then
		return false, `{label}: no scenario has that name, or the seed is not a number`
	end

	return Run.start(label, load)
end

--[[
    Runs one run to its end and returns its line, which is in the report too
--]]

function Program.run(scenario: string, seed: number): (boolean, string)
	local label: string, load: Load? = resolve(scenario, seed)
	if not load then
		local line: string = `{label}: no scenario has that name, or the seed is not a number`
		Run.record(line)
		return false, line
	end

	return Run.measure(label, load)
end

--[[
    Waits for a live server's first real player, gives every other device
    time to join, then runs every configured scenario for every seed in
    turn, with a pause between runs
--]]

function Program.all()
	local deadline: number = os.clock() + LIVE_JOIN_TIMEOUT
	while #Players:GetPlayers() == 0 and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
	end

	if #Players:GetPlayers() == 0 then
		Run.record(`{ARM} program: no player joined within {LIVE_JOIN_TIMEOUT} s, so nothing ran`)
		return
	end

	task.wait(LIVE_START_DELAY)

	for _, scenario: string in Config.program do
		for _, seed: number in Config.seeds do
			Program.run(scenario, seed)
			task.wait(PAUSE_SECONDS)
		end
	end

	Run.record(`{ARM} program: every run has finished`)
end

return Program
