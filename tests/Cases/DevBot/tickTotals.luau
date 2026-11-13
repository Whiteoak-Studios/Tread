--[[
    The bot harness sums the tick stages' rings tick by tick across the
    ring's wrap, oldest first, leaving out the between stage and one added
    after the relay, and takes no more ticks than the rings hold
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 4
local HEAD: number = 1 -- The ring index the next time goes at, so the newest sits at the ring's first and the wrap behind it
local NEWEST: number = 3

-- Each tick stage's time a ring index is that index times its own place value, so every sum reads its index back
local PLACES: { [string]: number } = { decode = 1, simulate = 10, npcs = 100, history = 1000, relay = 10000 }
local OTHER: number = 7 -- The place value of the stages left out, so any of their times would show in a sum
local STAGE_ORDER: { string } = { "decode", "simulate", "npcs", "history", "antiEsp", "relay", "bots" }
local EXPECTED: { number } = { 33333, 44444, 11111 } -- Ring indexes 3, 4 and then 1, past the wrap

-- One stage as the tick loop keeps it, its ring full and its head where the case puts it
local function stage(name: string, head: number, place: number): any
	local times: { number } = {}
	for index: number = 1, CAPACITY do
		table.insert(times, index * place)
	end

	return {
		name = name,
		run = function () end,
		between = false,
		label = name,
		times = times,
		held = CAPACITY,
		head = head,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	-- The between stage and the bots' stage hold their own heads and times, which must not reach the sums
	local stages: { any } = {}
	for _, name: string in STAGE_ORDER do
		local place: number? = PLACES[name]
		if place then
			table.insert(stages, stage(name, HEAD, place))
		else
			table.insert(stages, stage(name, CAPACITY - 1, OTHER))
		end
	end

	local totals: { number } = Run.tickTotals(stages, NEWEST)
	if table.concat(totals, ",") ~= table.concat(EXPECTED, ",") then
		return false,
			`The newest {NEWEST} ticks summed to {table.concat(totals, ",")}, not {table.concat(EXPECTED, ",")}`
	end

	local all: { number } = Run.tickTotals(stages, CAPACITY * 2)
	if #all ~= CAPACITY then
		return false, `Asked for more ticks than the rings hold, it summed {#all}, not the {CAPACITY} held`
	end

	return true, nil
end
