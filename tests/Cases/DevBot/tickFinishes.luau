--[[
    The bot harness sums each held tick's finish onto its tick's stages, up
    to a newest tick given, leaves an empty or stale finish ring adding
    nothing, and takes the finishes alone between two ticks across the wrap
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 8 -- Each stage's ring, which holds every tick the case runs
local TICKS: number = 6 -- Ticks every stage ran, 1 to 6
local SETTLED: number = 5 -- The newest tick whose work is all done, 6 still held

-- Each tick stage's time a tick is that tick times its own place value, and each finish's its tick times FINISH
local PLACES: { [string]: number } = { decode = 1, simulate = 10, npcs = 100, history = 1000, relay = 10000 }
local STAGE_ORDER: { string } = { "decode", "simulate", "npcs", "history", "antiEsp", "relay", "bots" }
local OTHER: number = 7 -- The place value of the stages left out, so any of their times would show in a sum
local FINISH: number = 100000

-- The finishes' ring: ticks 2 and 4 finished, 4 the newest at index 1 and 2 behind it past the wrap at index 4, and
-- the two indexes it doesn't hold set to a tick and a time that would show if read
local FINISH_TICKS: { number } = { 4, 3, 3, 2 }
local FINISH_HEAD: number = 1
local FINISH_HELD: number = 2
local UNHELD: number = 9999999 -- The time at the indexes the finishes' ring doesn't hold

-- Ticks 1 to 5, 2 and 4 with their finishes, 6 left for the next read since it is held
local WITH_FINISHES: { number } = { 11111, 222222, 33333, 444444, 55555 }
local STAGES_ALONE: { number } = { 11111, 22222, 33333, 44444, 55555, 66666 }
local NEWEST_TWO: { number } = { 444444, 55555 } -- Two ticks counted back from tick 5

-- One stage as the tick loop keeps it, every tick from 1 run into its ring from index 1
local function stage(name: string): any
	local place: number = PLACES[name] or OTHER
	local times: { number } = table.create(CAPACITY, 0)
	local ticks: { number } = table.create(CAPACITY, 0)

	for tick: number = 1, TICKS do
		times[tick] = tick * place
		ticks[tick] = tick
	end

	return {
		name = name,
		run = function () end,
		between = false,
		label = name,
		times = times,
		ticks = ticks,
		beats = table.create(CAPACITY, 0),
		held = TICKS,
		head = TICKS,
		last = TICKS * place,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	local stages: { any } = {}
	for _, name: string in STAGE_ORDER do
		table.insert(stages, stage(name))
	end

	local finishTimes: { number } = {}
	for index: number, tick: number in FINISH_TICKS do
		finishTimes[index] = UNHELD
		if index == FINISH_HEAD or index == #FINISH_TICKS then
			finishTimes[index] = tick * FINISH
		end
	end

	local finishes: any = {
		times = finishTimes,
		ticks = FINISH_TICKS,
		beats = table.create(#FINISH_TICKS, 0),
		held = FINISH_HELD,
		head = FINISH_HEAD,
		last = FINISH_TICKS[FINISH_HEAD] * FINISH,
	}

	local empty: any =
		{ times = table.create(4, 0), ticks = table.create(4, 0), beats = {}, held = 0, head = 0, last = 0 }

	-- 1) Each finished tick's finish on its total, the held tick past through left for the next read
	local summed: string = table.concat(Run.tickTotals(stages, SETTLED, finishes, SETTLED), ",")
	if summed ~= table.concat(WITH_FINISHES, ",") then
		return false, `Ticks 1 to {SETTLED} with their finishes summed to {summed}`
	end

	-- 2) No finishes, or a ring of none, sums the stages alone, as with workers off
	local alone: string = table.concat(Run.tickTotals(stages, TICKS), ",")
	local none: string = table.concat(Run.tickTotals(stages, TICKS, empty, nil), ",")
	if alone ~= table.concat(STAGES_ALONE, ",") or none ~= alone then
		return false, `With no finishes the ticks summed to {alone}, and with an empty ring to {none}`
	end

	-- 3) A short count back from through, and a finish older than the window adding nothing
	local newest: string = table.concat(Run.tickTotals(stages, #NEWEST_TWO, finishes, SETTLED), ",")
	if newest ~= table.concat(NEWEST_TWO, ",") then
		return false, `The two ticks back from {SETTLED} summed to {newest}, not {table.concat(NEWEST_TWO, ",")}`
	end

	-- 4) The finishes alone after a tick and through another, newest first, the unheld indexes never read
	local all: string = table.concat(Run.finishTimes(finishes, 0, SETTLED), ",")
	local later: string = table.concat(Run.finishTimes(finishes, 2, SETTLED), ",")
	local earlier: string = table.concat(Run.finishTimes(finishes, 0, 3), ",")
	local fromEmpty: number = #Run.finishTimes(empty, 0, SETTLED)

	if all ~= `{4 * FINISH},{2 * FINISH}` or later ~= `{4 * FINISH}` or earlier ~= `{2 * FINISH}` then
		return false, `The finishes alone read {all} through {SETTLED}, {later} after 2 and {earlier} through 3`
	elseif fromEmpty ~= 0 then
		return false, `An empty finish ring gave {fromEmpty} finishes`
	end

	return true, nil
end
