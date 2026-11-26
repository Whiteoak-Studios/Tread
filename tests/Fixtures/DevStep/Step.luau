--[[
    The step benchmark's cases' mount: BenchStep and its kinds' scenarios
    over a stand-in bot run that keeps each half it is asked for, beside the
    real levers on a started relay and anti-ESP, bots config and table
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
local BENCH_STEP_SPLIT: string = "dev/Server/Scenarios/BenchStepSplit.luau"
local BENCH_STEP_NPCS: string = "dev/Server/Scenarios/BenchStepNpcs.luau"
local BENCH_STEP_LEVERS: string = "dev/Server/Scenarios/BenchStepLevers.luau"
local BENCH_STEP_NEAR: string = "dev/Server/Scenarios/BenchStepNear.luau"
local LEVERS: string = "dev/Server/Bots/Levers.luau"
local WORKERS: number = 4 -- The relay workers the stand-in server started
local ANTI_ESP_WORKERS: number = 2 -- And the anti-ESP workers it made
local RELAY_BUDGET: number = 0.005 -- Its frame caps, the dev place's: seconds a relay run may take
local UNDER_LOAD_RUNS: number = 20 -- Relay runs in a row over that budget before the far band halves
local UNDER_LOAD_SCALE: number = 0.5
local NPC_BUDGET: number = 0.001 -- Seconds a tick's NPC steps may take
local PLACE_VERSION: number = 412
local JOB_ID: string = "job-1"

-- A half the stand-in run was asked for: its load, its name, the mode, the timing, and the live levers' states then:
-- step 1's, step 2's, how many bands the relay holds, whether it holds a crowd cap, whether anti-ESP packs for its
-- workers and whether verdict memory runs, and step 3's, whether the split is on, whether anti-ESP's slice runs whole,
-- the NPCs' budget, relay.budget and the far rate under load as runs/scale, each nil while off
export type Asked = {
	scenario: string,
	half: string?,
	workers: boolean,
	timing: any,
	lazy: boolean,
	checks: boolean,
	bands: number,
	crowd: boolean,
	antiEsp: boolean,
	memory: boolean,
	split: boolean,
	whole: boolean,
	npcBudget: number?,
	relayBudget: number?,
	underLoad: string?,
}

-- What the stand-in run gives back for a half, or throws
export type Answer = (scenario: string, half: string?) -> (boolean, string, { [string]: number }?)

export type Mounted = {
	BenchStep: (kind: string?) -> (boolean, string | nil),
	BenchStepNoise: () -> (boolean, string | nil),
	BenchStepSplit: () -> (boolean, string | nil),
	BenchStepNpcs: () -> (boolean, string | nil),
	BenchStepLevers: () -> (boolean, string | nil),
	BenchStepNear: () -> (boolean, string | nil),
	Levers: any,
	Commands: any, -- Tread's own, whose lazy decode is one of step 1's live levers
	Characters: any, -- Tread's own, whose owner checks are the other
	Relay: any, -- Tread's own, started on the Example's tables, whose bands, crowd cap, budget and far rate are levers
	AntiEsp: any, -- Tread's own on the Example's tables, whose workers, memory and whole slice are levers
	Npcs: any, -- Tread's own, whose budget is one of step 3's
	Tick: any, -- Tread's own, unstarted, whose split is the other
	Config: any, -- The bot harness's
	Compare: any,
	asked: { Asked },
	events: { string }, -- Each line BenchStep printed and each half asked for, as half <load>/<name>, in order
	settings: any, -- The stand-in server's settings, which the boot levers and step 3's ons read
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

-- The far rate under load as runs/scale, nil while off
local function underLoadOf(Relay: any): string?
	local underLoad: any = Relay.underLoad()
	if underLoad == nil then
		return nil
	end

	return `{underLoad.runs}/{underLoad.scale}`
end

-- The four frame caps a half asked for in one line: whether the slice ran whole, the NPCs' budget, relay.budget and
-- the far rate under load, as "true 0.001 0.005 20/0.5" with the stand-in server's settings or "false nil nil nil"
function Step.asked(asked: Asked): string
	return `{asked.whole} {asked.npcBudget} {asked.relayBudget} {asked.underLoad}`
end

-- The four frame caps as they stand on the real modules, in the same line
function Step.caps(mounted: Mounted): string
	local whole: boolean = mounted.AntiEsp.wholeOn()

	return `{whole} {mounted.Npcs.budget()} {mounted.Relay.budget()} {underLoadOf(mounted.Relay)}`
end

-- Turns the frame caps off as a flip off would, the far rate before the relay's budget it needs
function Step.capsOff(mounted: Mounted)
	mounted.Relay.setUnderLoad(nil)
	mounted.Relay.setBudget(nil)
	mounted.Npcs.setBudget(nil)
	mounted.AntiEsp.useWhole(false)
end

--[[
    Mounts BenchStep in a scope whose print keeps each line, its kinds'
    scenarios handed that one, and the real levers over stand-ins for the
    dev game, whose server started 4 relay workers with its clocks, the
    out-of-view rate and records as changes on, made 2 anti-ESP workers and
    has the dev place's bands, crowd cap and frame caps, and for
    the bot run, which answers each half as the answer given says. Anti-ESP
    is started on the Example's tables with every ray open, since verdict
    memory's switch refuses before start. The levers start as the dev
    server's do, the frame caps set in the order a flip on sets them and
    the split off
--]]

function Step.load(answer: Answer): Mounted
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local Commands: any = loaded.require(packages.Tread.Server.Commands)
	local Characters: any = loaded.require(packages.Tread.Server.Characters)
	local Relay: any = loaded.require(packages.Tread.Server.Relay)
	local AntiEsp: any = loaded.require(packages.Tread.Server.AntiEsp)
	local Npcs: any = loaded.require(packages.Tread.Server.Npcs)
	local Tick: any = loaded.require(packages.Tread.Server.Tick)
	local asked: { Asked } = {}
	local events: { string } = {}

	-- Lune's DataModel holds no default for either, which a live server's always has
	dataModel.PlaceVersion = PLACE_VERSION
	dataModel.JobId = JOB_ID

	-- The relay started on the Example's tables, whose two bands are the before half's
	loaded.require(dataModel:GetService("ServerScriptService").Fixtures.Relay.Harness).new()

	-- And anti-ESP on them, after the relay's harness started the slot table it reads, with no slice ever run
	local Example: any = loaded.require(dataModel:GetService("ServerScriptService").Fixtures.Config.Example)
	AntiEsp.start({ shared = Example.shared(), server = Example.server() }, {}, {}, function (): boolean
		return false
	end)

	local settings: any = {
		relay = { workers = WORKERS, clocks = true, changes = true, budget = RELAY_BUDGET },
		tiers = {
			bands = { { aim = 20, floor = 15 }, { aim = 10, floor = 10 }, { aim = 5, floor = 5 } },
			edges = { { enter = 350, leave = 385 }, { enter = 600, leave = 660 } },
			outOfView = { rate = 5, cone = 70, radius = 40 },
			crowd = { size = 32, rate = 20, floor = 5 },
			underLoad = { runs = UNDER_LOAD_RUNS, scale = UNDER_LOAD_SCALE },
		},
		antiEsp = { workers = ANTI_ESP_WORKERS, whole = true },
		npcs = { budget = NPC_BUDGET },
	}

	local run: any = {
		workers = function (): number
			return WORKERS
		end,

		runWorkers = function (scenario: string, timing: any, workers: boolean, _: any, half: string?): any
			local bands: { any } = Relay.bands()

			table.insert(asked, {
				scenario = scenario,
				half = half,
				workers = workers,
				timing = timing,
				lazy = Commands.lazyOn(),
				checks = Characters.checksOn(),
				bands = #bands,
				crowd = Relay.crowd() ~= nil,
				antiEsp = AntiEsp.workersOn(),
				memory = AntiEsp.memoryOn(),
				split = Tick.splitOn(),
				whole = AntiEsp.wholeOn(),
				npcBudget = Npcs.budget(),
				relayBudget = Relay.budget(),
				underLoad = underLoadOf(Relay),
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
		[server.Scenarios.BenchStepSplit] = BENCH_STEP_SPLIT,
		[server.Scenarios.BenchStepNpcs] = BENCH_STEP_NPCS,
		[server.Scenarios.BenchStepLevers] = BENCH_STEP_LEVERS,
		[server.Scenarios.BenchStepNear] = BENCH_STEP_NEAR,
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

	-- As the dev server starts them: step 1's live levers on, the relay on its own bands and crowd cap, anti-ESP
	-- casting in process, the split off and the frame caps on, in the order a flip on sets them, the relay's budget
	-- before its far rate
	Commands.useLazy(true)
	Characters.useChecks(true)
	Relay.setBands(settings.tiers.bands, settings.tiers.edges)
	Relay.setCrowd(settings.tiers.crowd)
	AntiEsp.useWorkers(false)
	Tick.useSplit(false)
	AntiEsp.useWhole(true)
	Npcs.setBudget(settings.npcs.budget)
	Relay.setBudget(settings.relay.budget)
	Relay.setUnderLoad(settings.tiers.underLoad)

	return {
		BenchStep = BenchStep,
		BenchStepNoise = load(server.Scenarios.BenchStepNoise),
		BenchStepSplit = load(server.Scenarios.BenchStepSplit),
		BenchStepNpcs = load(server.Scenarios.BenchStepNpcs),
		BenchStepLevers = load(server.Scenarios.BenchStepLevers),
		BenchStepNear = load(server.Scenarios.BenchStepNear),
		Levers = load(server.Bots.Levers),
		Commands = Commands,
		Characters = Characters,
		Relay = Relay,
		AntiEsp = AntiEsp,
		Npcs = Npcs,
		Tick = Tick,
		Config = loaded.require(server.Bots.Config),
		Compare = loaded.require(server.Bots.Compare),
		asked = asked,
		events = events,
		settings = settings,
	}
end

return Step
