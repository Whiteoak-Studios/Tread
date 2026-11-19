--[[
    The step benchmark's cases' mount: BenchStep and BenchStepNoise over a
    stand-in bot run that keeps each half it is asked for, beside the real
    levers, bots config and table, with every line BenchStep prints kept
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementMethod
local task = require("@lune/task")

local Harness = require("../DevServer/Harness")
local Kit = require("../Exploits/Kit")

local BENCH_STEP: string = "dev/Server/Scenarios/BenchStep.luau"
local BENCH_STEP_NOISE: string = "dev/Server/Scenarios/BenchStepNoise.luau"
local LEVERS: string = "dev/Server/Bots/Levers.luau"
local WORKERS: number = 4 -- The relay workers the stand-in server started
local PLACE_VERSION: number = 412
local JOB_ID: string = "job-1"

-- A half the stand-in run was asked for: its load, its name, the mode, the timing, and the live levers' states then
export type Asked = { scenario: string, half: string?, workers: boolean, timing: any, lazy: boolean, checks: boolean }

-- What the stand-in run gives back for a half, or throws
export type Answer = (scenario: string, half: string?) -> (boolean, string, { [string]: number }?)

export type Mounted = {
	BenchStep: (noise: boolean?) -> (boolean, string | nil),
	BenchStepNoise: () -> (boolean, string | nil),
	Levers: any,
	Commands: any, -- Tread's own, whose lazy decode is one of the session's live levers
	Characters: any, -- Tread's own, whose owner checks are the other
	Config: any, -- The bot harness's
	Compare: any,
	asked: { Asked },
	events: { string }, -- Each line BenchStep printed and each half asked for, as half <load>/<name>, in order
	settings: any, -- The stand-in server's settings, which the boot levers read
}

-- Lune's Players has no GetPlayers, so it answers with the Players parented to it, as the engine's does
pcall(roblox.implementMethod, "Players", "GetPlayers", function (players: any): { any }
	local found: { any } = {}
	for _, child: any in players:GetChildren() do
		if child:IsA("Player") then
			table.insert(found, child)
		end
	end

	return found
end)

local Step = {}

--[[
    Mounts BenchStep in a scope whose print keeps each line, BenchStepNoise
    handed that one, and the real levers over stand-ins for the dev game,
    whose server started 4 relay workers with its clocks, the out-of-view
    rate and records as changes on, and for the bot run, which answers
    each half as the answer given says. Both live levers start on
--]]

function Step.load(answer: Answer): Mounted
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local Commands: any = loaded.require(packages.Tread.Server.Commands)
	local Characters: any = loaded.require(packages.Tread.Server.Characters)
	local asked: { Asked } = {}
	local events: { string } = {}

	-- Lune's DataModel holds no default for either, which a live server's always has
	dataModel.PlaceVersion = PLACE_VERSION
	dataModel.JobId = JOB_ID

	local settings: any = {
		relay = { workers = WORKERS, clocks = true, changes = true },
		tiers = { outOfView = { rate = 5, cone = 70, radius = 40 } },
	}

	local run: any = {
		workers = function (): number
			return WORKERS
		end,

		runWorkers = function (scenario: string, timing: any, workers: boolean, _: any, half: string?): any
			table.insert(asked, {
				scenario = scenario,
				half = half,
				workers = workers,
				timing = timing,
				lazy = Commands.lazyOn(),
				checks = Characters.checksOn(),
			})

			table.insert(events, `half {scenario}/{half}`)

			return answer(scenario, half)
		end,
	}

	local stand: any = {
		get = function (): (any, any, any)
			return {}, {}, settings
		end,
	}

	local files: { [any]: string } = {
		[server.Bots.Levers] = LEVERS,
		[server.Scenarios.BenchStepNoise] = BENCH_STEP_NOISE,
	}

	local results: { [any]: any } = { [server.Bots.Run] = run, [server.Game] = stand }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)

	local scope: { [string]: any } = {
		game = dataModel,
		script = server.Scenarios.BenchStep,
		require = load,
		task = task,

		print = function (line: string)
			table.insert(events, line)
		end,
	}

	local chunk: () -> any = luau.load(fs.readFile(BENCH_STEP), { debugName = BENCH_STEP, environment = scope })
	local BenchStep: any = chunk()
	results[server.Scenarios.BenchStep] = BenchStep

	Commands.useLazy(true)
	Characters.useChecks(true)

	return {
		BenchStep = BenchStep,
		BenchStepNoise = load(server.Scenarios.BenchStepNoise),
		Levers = load(server.Bots.Levers),
		Commands = Commands,
		Characters = Characters,
		Config = loaded.require(server.Bots.Config),
		Compare = loaded.require(server.Bots.Compare),
		asked = asked,
		events = events,
		settings = settings,
	}
end

return Step
