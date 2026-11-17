--[[
    Over a window whose catch-up Heartbeat skipped the relay, the bot panel
    sums each tick's stages with no relay on the skipped tick, and reads the
    relay's high end over its own runs since the window opened
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 4
local ELAPSED: number = 0.1 -- Seconds the window's frames span
local SKIPS: string = "relay" -- The stage a catch-up Heartbeat's earlier ticks skip

-- Each stage's time a tick is that tick times its place value, so every figure reads its ticks back
local PLACES: { [string]: number } = { decode = 1, simulate = 10, npcs = 100, history = 1000, relay = 10000 }
local STAGE_ORDER: { string } = { "decode", "simulate", "npcs", "history", "relay" }

-- Each Heartbeat's ticks, two on a catch-up one, the window opening after OPENED of them
local HEARTBEATS: { { number } } = { { 1 }, { 2, 3 }, { 4 }, { 5, 6 } }
local OPENED: number = 2
local TICKS: number = 3 -- Ticks 4 to 6, the window's
local FRAMES: { number } = { 50, 50 } -- Its two Heartbeats' intervals, ms

-- Milliseconds: ticks 4 to 6 total 44444, 5555 with the relay skipped, and 66666, in seconds
local TOTAL_MEDIAN: number = 44444 * 1000
local TOTAL_HIGH: number = 66666 * 1000

-- Milliseconds: each stage's largest time over its runs in the window, the relay's on ticks 4 and 6 alone
local HIGHS: { [string]: number } = {
	decode = 6 * 1000,
	simulate = 60 * 1000,
	npcs = 600 * 1000,
	history = 6000 * 1000,
	relay = 60000 * 1000,
}

-- One stage as the tick loop makes it, its ring still empty
local function empty(name: string): any
	return {
		name = name,
		run = function () end,
		between = false,
		label = name,
		times = table.create(CAPACITY, 0),
		ticks = table.create(CAPACITY, 0),
		held = 0,
		head = 0,
		last = 0,
	}
end

-- Each stage's ring after the Heartbeats given, written as the tick loop writes it, the relay on each one's last tick
local function heartbeats(rings: { any }, from: number, to: number)
	for index: number = from, to do
		local heartbeat: { number } = HEARTBEATS[index]

		for at: number, tick: number in heartbeat do
			for _, ring: any in rings do
				if ring.name == SKIPS and at < #heartbeat then
					continue
				end

				local time: number = tick * PLACES[ring.name]
				ring.times[ring.head + 1] = time
				ring.ticks[ring.head + 1] = tick
				ring.head = (ring.head + 1) % CAPACITY
				ring.held = math.min(ring.held + 1, CAPACITY)
				ring.last = time
			end
		end
	end
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared

	-- Stand-ins for the dev game, its fleet and the dev scope, whose real modules start the dev game's server
	local files: { [any]: string } = { [server.BotPanel] = BOT_PANEL, [server.Bots.Run] = RUN }
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {}, [shared.Network.Server] = {} }
	local BotPanel: any = Kit.loader(dataModel, files, results, loaded.require)(server.BotPanel)

	local stages: { any } = {}
	for _, name: string in STAGE_ORDER do
		table.insert(stages, empty(name))
	end

	-- The window opens with each ring's head where the first Heartbeats left it, as the panel's open reads them
	heartbeats(stages, 1, OPENED)

	local heads: { [string]: number } = {}
	for _, stage: any in stages do
		heads[stage.name] = stage.head
	end

	heartbeats(stages, OPENED + 1, #HEARTBEATS)

	local read: any = BotPanel.read(table.clone(FRAMES), ELAPSED, stages, heads, TICKS)
	if read.totalMedian ~= TOTAL_MEDIAN or read.totalHigh ~= TOTAL_HIGH then
		return false, `The skipping window's tick totals read as p50 {read.totalMedian} and p95 {read.totalHigh} ms`
	end

	for name: string, high: number in HIGHS do
		if read.stages[name] ~= high then
			return false, `{name}'s p95 over the skipping window read as {read.stages[name]} ms, not {high}`
		end
	end

	return true, nil
end
