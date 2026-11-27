--[[
    On a server with relay workers the bot panel sums each held tick's finish
    onto its tick, the tick still held left for the next window, and shows
    the finish's high end since the window opened beside the stages
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 4
local ELAPSED: number = 0.1 -- Seconds the window's frames span
local FRAMES: { number } = { 50, 50 } -- Its two Heartbeats' intervals, ms

-- Each stage's time a tick is that tick times its place value, and each finish's that tick times FINISH
local PLACES: { [string]: number } = { decode = 1, simulate = 10, npcs = 100, history = 1000, relay = 10000 }
local STAGE_ORDER: { string } = { "decode", "simulate", "npcs", "history", "relay" }
local FINISH: number = 100000

-- Ticks 1 to 4 ran, each held, the first three finished, the window opening once tick 1 had finished
local TICKS: number = 4
local FINISHED: number = 3
local OPENED: number = 1

-- Milliseconds: ticks 2 and 3, each with its finish, in seconds
local TOTAL_MEDIAN: number = 222222 * 1000
local TOTAL_HIGH: number = 333333 * 1000
local FINISH_HIGH: number = 300000 * 1000 -- The finishes since the window opened, ticks 2 and 3

-- A ring of size CAPACITY with each tick from 1 to count, its time that tick times place
local function ring(count: number, place: number): any
	local times: { number } = table.create(CAPACITY, 0)
	local ticks: { number } = table.create(CAPACITY, 0)
	for tick: number = 1, count do
		times[tick] = tick * place
		ticks[tick] = tick
	end

	return {
		times = times,
		ticks = ticks,
		beats = table.create(CAPACITY, 0),
		held = count,
		head = count % CAPACITY,
		last = count * place,
	}
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
	local heads: { [string]: number } = {}
	for _, name: string in STAGE_ORDER do
		local stage: any = ring(TICKS, PLACES[name])
		stage.name = name
		stage.run = function () end
		stage.between = false
		stage.label = name
		table.insert(stages, stage)
		heads[name] = OPENED
	end

	local finishes: any = ring(FINISHED, FINISH)
	local finished: any = { ring = finishes, head = OPENED, through = FINISHED }

	-- 1) The window's ticks done, each with its finish, the held one left out
	local read: any = BotPanel.read(table.clone(FRAMES), ELAPSED, stages, heads, FINISHED - OPENED, finished)
	if read.totalMedian ~= TOTAL_MEDIAN or read.totalHigh ~= TOTAL_HIGH then
		return false, `With finishes the tick totals read as p50 {read.totalMedian} and p95 {read.totalHigh} ms`
	elseif read.stages.finish ~= FINISH_HIGH then
		return false, `The finish's p95 since the window opened read as {read.stages.finish} ms, not {FINISH_HIGH}`
	end

	-- 2) Beside the stages, the finish's high end
	local lines: { string } = string.split(BotPanel.describe(read, 2.25, 1, 12), "\n")
	local beside: string = `Beside them, p95 ms: finish {string.format("%.3f", FINISH_HIGH)}`
	if lines[5] ~= beside then
		return false, `The panel's line beside the stages read {lines[5]}, not {beside}`
	end

	-- 3) Without finishes, as on a server with no workers, no finish is read or shown
	local serial: any = BotPanel.read(table.clone(FRAMES), ELAPSED, stages, heads, FINISHED - OPENED)
	if serial.stages.finish ~= nil then
		return false, "A read with no finishes still read a finish"
	end

	return true, nil
end
