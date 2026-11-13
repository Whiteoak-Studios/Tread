--[[
    The bot panel on the dev server: a player's spawns and clears of the
    panel's own bots, each refused while a run could meet them, and the
    server's frame and tick-stage numbers once a second to each watcher
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Tick = require(Packages.Tread.Server.Tick)

local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Run = require(ServerScriptService.Server.Bots.Run)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local CAP: number = require(ServerScriptService.Server.Config.BotPanel).cap
local TRIES: number = require(ServerScriptService.Server.Config.BotPanel).tries
local INTERVAL: number = require(ServerScriptService.Server.Config.BotPanel).interval
local MEDIAN: number = require(ServerScriptService.Server.Config.BotPanel).median
local HIGH: number = require(ServerScriptService.Server.Config.BotPanel).high
local REASON_BYTES: number = require(ServerScriptService.Server.Config.BotPanel).reasonBytes
local RATES: { spawn: Rate, clear: Rate, watch: Rate } = require(ServerScriptService.Server.Config.BotPanel).rates
local BATCH: number = require(ServerScriptService.Server.Bots.Config).spawn.batch
local LIFT: number = require(ServerScriptService.Server.Bots.Config).spawn.lift
local PROBE: number = require(ServerScriptService.Server.Bots.Config).spawn.probe
local TICK_STAGES: { string } = require(ServerScriptService.Server.Bots.Config).tick.stages
local BESIDE: string = require(ServerScriptService.Server.Bots.Config).tick.beside
local BOTS_STAGE: string = require(ServerScriptService.Server.Bots.Config).stage

-- The harness's whole map, which S2 spreads its bots over
local MAP: Config.Area = require(ServerScriptService.Server.Bots.Config).scenarios.S2.groups[1].spawn

local GROUP: string = "panel" -- The fleet group every panel bot belongs to
local TURN: number = 2 * math.pi
local MILLISECONDS: number = 1000 -- A second's, which every time shows in
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local FIGURE: string = "%.3f" -- Each time as the panel shows it
local RATE: string = "%.1f" -- The Heartbeats a second
local SEPARATOR: string = ", " -- Between the stages of one line
local PARTS: string = "; " -- Between the parts of a refusal
local NEWLINE: string = "\n"

-- The stages shown beside the tick stages, whose times never join their total
local SHOWN_BESIDE: { string } = { BESIDE, BOTS_STAGE }

type Area = Config.Area
type Key = Player | Volt.Bot
type Rate = { perSecond: number, burst: number }

-- How a spawn's bots move, as the botSpawn event names it
type Behavior = "Idle" | "Walk" | "Sprint"

-- What a spawn ask meets on the server
export type State = {
	running: string?, -- The live run going, nil while none is
	building: boolean, -- Whether a spawn is still building its bots
	made: number, -- The panel's bots on the server
	foreign: number, -- Bots a run made on the server
}

-- The server's numbers over one window, each time in milliseconds
export type Read = {
	rate: number, -- Heartbeats a second
	frameMedian: number,
	frameHigh: number,
	ticks: number, -- Ticks run
	totalMedian: number, -- The tick stages' summed time a tick
	totalHigh: number,
	stages: { [string]: number }, -- Each shown stage's high end over its own runs, for the stages the tick has
}

local Made: number = 0 -- The panel's bots on the server, which the fleet holds alone while there are any
local Building: boolean = false -- Whether a spawn is building, beside which nothing else spawns or clears
local Spawned: number = 0 -- Bots the panel ever built, each bot's own number and seed
local LiveRun: (() -> string?)? = nil -- The live panel's run going, from the start
local Started: boolean = false

local Watchers: { [Player]: boolean } = {} -- The players whose panel shows
local Beats: RBXScriptConnection? = nil -- The window's Heartbeat listener, connected while anyone watches
local Frames: { number } = {} -- The window's Heartbeat intervals, milliseconds
local Elapsed: number = 0 -- The window's seconds
local Ticks: number = 0 -- The ticks run when the window opened
local Heads: { [string]: number } = {} -- Each stage's ring head when the window opened

local BotPanel = {}

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

-- A ring's times since its head stood at head, in seconds, no more than the ring holds
local function since(stage: Tick.Stage, head: number): { number }
	local capacity: number = #stage.times
	local runs: number = math.min((stage.head - head) % capacity, stage.held)
	local times: { number } = {}

	for back: number = runs, 1, -1 do
		table.insert(times, stage.times[(stage.head - back) % capacity + 1])
	end

	return times
end

--[[
    Why the server refuses a spawn of count bots, nil when it doesn't: the
    live run going first, then a spawn still building, a run's bots on the
    server, a count past the cap, and the panel's bots with it past the cap
--]]

function BotPanel.refusal(state: State, count: number): string?
	local running: string? = state.running
	if running then
		return `{running} is running on the live panel, so the panel spawns nothing until it ends`
	elseif state.building then
		return "a spawn is still building, so the next waits for it"
	elseif state.foreign > 0 then
		return `{state.foreign} bots a run made are on the server, so the panel spawns none beside them`
	elseif count < 1 or count % 1 ~= 0 then
		return `{count} is no count of bots, which is a whole number from 1`
	elseif count > CAP then
		return `a count of {count} is past the panel's cap of {CAP}`
	elseif state.made + count > CAP then
		return `{state.made} panel bots and {count} more would pass the panel's cap of {CAP}`
	end

	return nil
end

-- Whether the panel's bots are on the server or a spawn of them is building, beside which no run starts
function BotPanel.holds(): boolean
	return Made > 0 or Building
end

--[[
    The server's numbers over one window: its Heartbeats a second and its
    frame times' middle and high end, the tick stages' sums over the ticks
    it ran, and each shown stage's high end over its own runs since its
    ring's head stood where heads has it, 0 for a stage added since. It
    sorts frames in place
--]]

function BotPanel.read(
	frames: { number },
	elapsed: number,
	stages: { Tick.Stage },
	heads: { [string]: number },
	ticks: number
): Read
	local totals: { number } = {}
	for _, total: number in Run.tickTotals(stages, ticks) do
		table.insert(totals, total * MILLISECONDS)
	end

	local highs: { [string]: number } = {}
	for _, stage: Tick.Stage in stages do
		if table.find(TICK_STAGES, stage.name) or table.find(SHOWN_BESIDE, stage.name) then
			highs[stage.name] = percentile(since(stage, heads[stage.name] or 0), HIGH) * MILLISECONDS
		end
	end

	return {
		rate = #frames / elapsed,
		frameMedian = percentile(frames, MEDIAN),
		frameHigh = percentile(frames, HIGH),
		ticks = ticks,
		totalMedian = percentile(totals, MEDIAN),
		totalHigh = percentile(totals, HIGH),
		stages = highs,
	}
end

local function figure(time: number): string
	return string.format(FIGURE, time)
end

-- Each named stage's high end in one line, the stages the tick lacks left out
local function times(read: Read, names: { string }): string
	local parts: { string } = {}
	for _, name: string in names do
		local time: number? = read.stages[name]
		if time then
			table.insert(parts, `{name} {figure(time)}`)
		end
	end

	return table.concat(parts, SEPARATOR)
end

--[[
    The numbers as the panel shows them, a line each: the frames, the
    Heartbeat's own work, the tick stages' total, each stage's high end,
    and the real players and bots on the server

    @ heartbeatTime | Stats.HeartbeatTime in milliseconds
--]]

function BotPanel.describe(read: Read, heartbeatTime: number, real: number, bots: number): string
	local median: string = `p{math.round(MEDIAN * PERCENT)}`
	local high: string = `p{math.round(HIGH * PERCENT)}`
	local frames: string = `frame ms {median} {figure(read.frameMedian)} {high} {figure(read.frameHigh)}`
	local total: string = `tick stages a tick ms {median} {figure(read.totalMedian)} {high} {figure(read.totalHigh)}`

	local lines: { string } = {
		`{string.format(RATE, read.rate)} Heartbeats a second, {frames}`,
		`Stats.HeartbeatTime {figure(heartbeatTime)} ms`,
		`{read.ticks} ticks, {total}`,
		`{high} ms: {times(read, TICK_STAGES)}`,
		`Beside them, {high} ms: {times(read, SHOWN_BESIDE)}`,
		`{real} real players, {bots} bots`,
	}

	return table.concat(lines, NEWLINE)
end

-- A new window from now: no frames yet, and the ticks run and each stage's ring head as they stand
local function open()
	local ran: number = Tick.counts()
	Frames = {}
	Elapsed = 0
	Ticks = ran
	Heads = {}

	for _, stage: Tick.Stage in Tick.stages() do
		Heads[stage.name] = stage.head
	end
end

--[[
    Each Heartbeat while anyone watches: its interval joins the window, and
    once the window spans the interval, a new one opens and the numbers over
    the one before go to every watcher with the panel's bots on the server
--]]

local function beat(delta: number)
	table.insert(Frames, delta * MILLISECONDS)
	Elapsed += delta

	if Elapsed < INTERVAL then
		return
	end

	-- A new window first, so a read that throws still leaves the next one empty
	local frames: { number } = Frames
	local elapsed: number = Elapsed
	local heads: { [string]: number } = Heads
	local opened: number = Ticks
	open()

	-- Stats.HeartbeatTime is in seconds, and the panel shows milliseconds
	local heartbeatTime: number = Stats.HeartbeatTime * MILLISECONDS
	local read: Read = BotPanel.read(frames, elapsed, Tick.stages(), heads, Ticks - opened)
	local text: string = BotPanel.describe(read, heartbeatTime, #Players:GetPlayers(), #Fleet.entries())

	for player: Player in Watchers do
		Network.botStats.fire(player, Made, text)
	end
end

-- Tells a player why the panel refused them, cut to what the event carries
local function refuse(player: Player, reason: string)
	Network.botRefused.fire(player, string.sub(reason, 1, REASON_BYTES))
end

-- What a spawn ask meets now
local function state(): State
	local running: string? = nil
	local liveRun: (() -> string?)? = LiveRun
	if liveRun then
		running = liveRun()
	end

	return {
		running = running,
		building = Building,
		made = Made,
		foreign = math.max(#Fleet.entries() - Made, 0),
	}
end

-- A point of the area over ground, on that ground and facing a drawn way, nil when every try is over nothing
local function groundIn(area: Area, own: Seeded.Seeded, params: RaycastParams): CFrame?
	local halfWidth: number = area.size.X / 2
	local halfDepth: number = area.size.Y / 2

	for _ = 1, TRIES do
		local x: number = area.center.X + own:number(-halfWidth, halfWidth)
		local z: number = area.center.Z + own:number(-halfDepth, halfDepth)
		local origin: Vector3 = Vector3.new(x, area.center.Y + PROBE, z)

		-- Cast down from PROBE above the area's height to as far below it
		local hit: RaycastResult? = Workspace:Raycast(origin, Vector3.new(0, -2 * PROBE, 0), params)
		if hit then
			return CFrame.new(x, hit.Position.Y + LIFT, z) * CFrame.Angles(0, own:number(0, TURN), 0)
		end
	end

	return nil
end

-- How a bot of the behavior steers: Idle stands, Walk and Sprint roam the area at their speed
local function steerOf(behavior: Behavior, area: Area, own: Seeded.Seeded, shared: Tread.Shared): Programs.Steer
	if behavior == "Idle" then
		return Programs.idle()
	end

	local sprint: boolean = behavior == "Sprint"
	local speed: number = sprint and shared.step.sprint or shared.step.walk

	return Programs.roam(area, own, {
		speed = speed,
		rate = shared.rates.simulation,
		sprint = sprint,
		crouch = false,
		long = false,
	})
end

--[[
    Builds a spawn's bots a batch a frame, each at a drawn point of the
    area over ground, its own number seeding its draws. A bot whose tries
    all miss the ground, or whose build fails, is left out, and the player
    is told how many of each there were in one refusal
--]]

local function build(player: Player, area: Area, count: number, behavior: Behavior, testContent: Instance)
	local _, shared: Tread.Shared = Game.get()
	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { testContent, Workspace.Terrain }
	params.RespectCanCollide = true

	local missed: number, failed: number = 0, 0
	local failure: string? = nil -- The first build's failure

	for index: number = 1, count do
		Spawned += 1

		local own: Seeded.Seeded = Seeded.new(Spawned)
		local at: CFrame? = groundIn(area, own, params)

		if at then
			local plan: Fleet.Plan = {
				name = `PanelBot{Spawned}`,
				group = GROUP,
				at = at,
				steer = steerOf(behavior, area, own, shared),
				faults = nil,
				seed = Spawned,
			}

			local added: boolean, problem: any = pcall(Fleet.add, plan)

			if added then
				Made += 1
			else
				failed += 1
				failure = failure or tostring(problem)
			end
		else
			missed += 1
		end

		-- A frame between batches, so a large spawn never holds the server past the engine's script timeout
		if index % BATCH == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	local left: { string } = {}
	if missed > 0 then
		table.insert(left, `{missed} found no ground in {TRIES} tries`)
	end

	if failure then
		table.insert(left, `{failed} failed to build, the first with: {failure}`)
	end

	if #left > 0 then
		refuse(player, `{count - missed - failed} of the {count} bots were built: {table.concat(left, PARTS)}`)
	end
end

--[[
    A player's ask to spawn bots, refused with the reason while a run could
    meet them or past the cap, and otherwise built over the whole map or the
    square radius studs either way of their character. Nothing else spawns
    or clears while it builds, whatever the build does
--]]

local function spawn(key: Key, count: number, behavior: Behavior, radius: number?)
	-- A Volt bot fires none of the dev scope's events, so whoever asked is a player
	local player: Player = key :: Player
	local refusal: string? = BotPanel.refusal(state(), count)
	if refusal then
		return refuse(player, refusal)
	end

	-- The dev game's casts meet its test content, where the ground is
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	if not testContent then
		return refuse(player, "Workspace.TestContent is missing, so the panel finds no ground for the bots")
	end

	local area: Area = MAP
	if radius then
		local character: Tread.Character? = Game.characterOf(player)
		if not character then
			return refuse(player, "you have no character to spawn the bots around")
		end

		-- A character that died or slept refuses the read
		local read: boolean, standing: Tread.State? = pcall(character.getState, character)
		if not read or not standing then
			return refuse(player, "your character's state can't be read, so the bots have nowhere to spawn around")
		end

		local across: number = 2 * radius -- The square's side, radius either way of the character
		area = { center = standing.root, size = Vector2.new(across, across) }
	end

	Building = true
	local built: boolean, failure: any = pcall(build, player, area, count, behavior, testContent)
	Building = false

	if not built then
		refuse(player, `the spawn stopped part way, {Made} panel bots on the server: {failure}`)
	end
end

--[[
    A player's ask to remove every bot the panel made, refused while a
    spawn builds, while the panel has none, and while bots a run made share
    the fleet, which Clear would take too
--]]

local function clear(key: Key)
	local player: Player = key :: Player
	local foreign: number = #Fleet.entries() - Made

	if Building then
		return refuse(player, "a spawn is still building, so Clear waits for it")
	elseif Made == 0 then
		return refuse(player, "the panel has no bots on the server to clear")
	elseif foreign > 0 then
		return refuse(player, `{foreign} bots a run made share the fleet, so Clear waits for the run to end`)
	end

	Made = 0

	for _, problem: string in Fleet.clear() do
		warn(`The bot panel's Clear left a problem: {problem}`)
	end
end

-- A player stops watching, their panel hidden or they left, and the window's listener goes with the last one
local function forget(key: Key)
	Watchers[key :: Player] = nil

	local beats: RBXScriptConnection? = Beats
	if beats and next(Watchers) == nil then
		beats:Disconnect()
		Beats = nil
	end
end

-- A player's panel showing or hidden, the first watcher opening a window and connecting its listener
local function watch(key: Key, shown: boolean)
	if not shown then
		return forget(key)
	end

	Watchers[key :: Player] = true

	if not Beats then
		open()
		Beats = RunService.Heartbeat:Connect(beat)
	end
end

--[[
    Binds the panel's asks at the dev game's own rates, each spawn on a
    thread of its own, and forgets each player who leaves, whose bots stay.
    running gives the live panel's run going. It runs once a server, and
    its listeners live as long as the server
--]]

function BotPanel.start(running: () -> string?)
	if Started then
		error("BotPanel.start runs once a server, and it has already run", 2)
	end

	Started = true
	LiveRun = running

	Network.rate("botSpawn", RATES.spawn.perSecond, RATES.spawn.burst)
	Network.rate("botClear", RATES.clear.perSecond, RATES.clear.burst)
	Network.rate("botWatch", RATES.watch.perSecond, RATES.watch.burst)

	Network.botSpawn.on(function (key: Key, count: number, behavior: Behavior, radius: number?)
		task.spawn(spawn, key, count, behavior, radius)
	end)

	Network.botClear.on(clear)
	Network.botWatch.on(watch)
	Network.onLeave(forget)
end

return BotPanel
