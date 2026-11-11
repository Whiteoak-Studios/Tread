--[[
    The bot panel reads a window's Heartbeats a second and frame times, the
    tick stages' sums and each stage's high end from their rings across the
    wrap, and shows them a line each in the panel's own words
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 4
local ELAPSED: number = 0.1 -- Seconds the window's four frames span
local TICKS: number = 3 -- Ticks the window ran

-- Each Heartbeat's interval, ms, out of order so the read sorts them
local FRAMES: { number } = { 30, 10, 40, 20 }

-- Each stage's time at a ring index is that index times its own place value, so every figure reads its indexes back
local PLACES: { [string]: number } = {
	decode = 1,
	simulate = 10,
	npcs = 100,
	history = 1000,
	relay = 10000,
	antiEsp = 7,
	bots = 3,
	other = 5,
}

-- Each stage's ring head and the times it holds now, and its head as the window opened, nil for one added since
type Ring = { name: string, head: number, held: number, opened: number? }

local RINGS: { Ring } = {
	-- The tick stages ran the window's 3 ticks into ring indexes 3, 4 and then 1, past the wrap
	{ name = "decode", head = 1, held = 4, opened = 2 },
	{ name = "simulate", head = 1, held = 4, opened = 2 },
	{ name = "npcs", head = 1, held = 4, opened = 2 },
	{ name = "history", head = 1, held = 4, opened = 2 },

	-- The between stage ran twice, into indexes 2 and 3
	{ name = "antiEsp", head = 3, held = 4, opened = 1 },
	{ name = "relay", head = 1, held = 4, opened = 2 },

	-- The bots' stage was added during the window, and ran into indexes 1 and 2
	{ name = "bots", head = 2, held = 2, opened = nil },

	-- A stage the panel never shows
	{ name = "other", head = 1, held = 4, opened = 2 },
}

-- Milliseconds: indexes 3, 4 and 1 summed over the tick stages' place values, 11,111 each, in seconds
local TOTAL_MEDIAN: number = 33333 * 1000
local TOTAL_HIGH: number = 44444 * 1000

-- Milliseconds: each stage's largest time since its ring's head stood where the window opened it
local HIGHS: { [string]: number } = {
	decode = 4 * 1000,
	simulate = 40 * 1000,
	npcs = 400 * 1000,
	history = 4000 * 1000,
	relay = 40000 * 1000,
	antiEsp = 21 * 1000,
	bots = 6 * 1000,
}

-- A read the text is shown from, the bots' stage left out, as before the fleet's first bot
local SHOWN: { [string]: any } = {
	rate = 59.94,
	frameMedian = 16.6667,
	frameHigh = 17.5,
	ticks = 20,
	totalMedian = 1.2346,
	totalHigh = 2.5,
	stages = { decode = 0.1, simulate = 0.5, npcs = 0.01, history = 0.05, relay = 0.4, antiEsp = 0.3 },
}

local TEXT: string = table.concat({
	"59.9 Heartbeats a second, frame ms p50 16.667 p95 17.500",
	"Stats.HeartbeatTime 2.250 ms",
	"20 ticks, tick stages a tick ms p50 1.235 p95 2.500",
	"p95 ms: decode 0.100, simulate 0.500, npcs 0.010, history 0.050, relay 0.400",
	"Beside them, p95 ms: antiEsp 0.300",
	"1 real players, 12 bots",
}, "\n")

local HEARTBEAT_TIME: number = 2.25 -- Milliseconds, as the panel's send hands it over from the seconds Stats reads
local REAL: number = 1
local BOTS: number = 12

-- One stage as the tick loop keeps it, its ring the size the case gives
local function stage(ring: Ring): any
	local times: { number } = {}
	for index: number = 1, CAPACITY do
		table.insert(times, index * PLACES[ring.name])
	end

	return {
		name = ring.name,
		run = function () end,
		between = ring.name == "antiEsp",
		label = ring.name,
		times = times,
		held = ring.held,
		head = ring.head,
		last = 0,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local config: any = loaded.require(server.Config.BotPanel)

	if config.median ~= 0.5 or config.high ~= 0.95 then
		return false,
			`The case's answers are a p50 and a p95, and the config's shares are {config.median} and {config.high}`
	end

	-- Stand-ins for the dev game, its fleet and the dev scope, whose real modules start the dev game's server
	local files: { [any]: string } = { [server.BotPanel] = BOT_PANEL, [server.Bots.Run] = RUN }
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {}, [shared.Network.Server] = {} }
	local BotPanel: any = Kit.loader(dataModel, files, results, loaded.require)(server.BotPanel)

	local stages: { any } = {}
	local heads: { [string]: number } = {}
	for _, ring: Ring in RINGS do
		table.insert(stages, stage(ring))

		local opened: number? = ring.opened
		if opened then
			heads[ring.name] = opened
		end
	end

	-- 1) The frames: four in a tenth of a second, their middle and high end by nearest rank
	local read: any = BotPanel.read(table.clone(FRAMES), ELAPSED, stages, heads, TICKS)
	if read.rate ~= #FRAMES / ELAPSED then
		return false, `{#FRAMES} Heartbeats over {ELAPSED} s read as {read.rate} a second`
	elseif read.frameMedian ~= 20 or read.frameHigh ~= 40 then
		return false, `The frames {table.concat(FRAMES, ",")} read as p50 {read.frameMedian} and p95 {read.frameHigh}`
	elseif read.ticks ~= TICKS then
		return false, `The read gave {read.ticks} ticks, not {TICKS}`
	end

	-- 2) The tick stages' sums across the wrap, the between stage, the bots' and the unshown one left out
	if read.totalMedian ~= TOTAL_MEDIAN or read.totalHigh ~= TOTAL_HIGH then
		return false, `The tick totals read as p50 {read.totalMedian} and p95 {read.totalHigh} ms`
	end

	-- 3) Each shown stage's high end over its own runs since the window opened, and no other stage
	for name: string, high: number in HIGHS do
		if read.stages[name] ~= high then
			return false, `{name}'s p95 read as {read.stages[name]} ms, not {high}`
		end
	end

	if read.stages.other ~= nil then
		return false, "A stage the panel never shows was read"
	end

	-- 4) The text, a line each, the stage the tick lacks left out
	local text: string = BotPanel.describe(SHOWN, HEARTBEAT_TIME, REAL, BOTS)
	if text ~= TEXT then
		return false, `The panel's numbers read:\n{text}`
	end

	return true, nil
end
