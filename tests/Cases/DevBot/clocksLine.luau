--[[
    The bot harness pushes each read's relay clocks as clock <name>Ms and
    prints them in one line in the relay's fixed section order, and with
    no read carrying them pushes nothing and prints no line
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local LABEL: string = "Bots S4 seed 1"
local MILLISECONDS: number = 1000
local FIRST: number = 0.25 -- Seconds the first read gives each section for each place in the order, the second twice

-- The relay's sections in the order its clocks lay them out
local ORDER: { string } = {
	"head",
	"gather",
	"measure",
	"settle",
	"schedule",
	"place",
	"send",
	"unpack",
	"bodies",
	"grid",
	"ready",
	"turns",
	"views",
	"pack",
	"run",
	"fire",
	"walk",
	"file",
	"inProcess",
	"answers",
	"shared",
	"own",
	"handIn",
	"flushTick",
	"open",
	"land",
	"asks",
	"sends",
	"deferred",
	"flushFinish",
	"round",
	"waitBeat",
	"delivery",
	"back",
}

-- A read whose relayClocks gives each section its place in the order times seconds, as last and as p95
local function read(seconds: number): { [string]: any }
	local clocks: { [string]: any } = {}
	for index: number, name: string in ORDER do
		clocks[name] = { last = index * seconds, p95 = index * seconds }
	end

	return { ticks = 20, relaySkipped = 0, stages = {}, relayClocks = clocks }
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	-- 1) Two reads: each section's samples are its place times 250 ms and 500 ms, so p50 is the first and p95 and p99
	-- the second
	local samples: { [string]: { number } } = {}
	Run.clocks(read(FIRST), samples)
	Run.clocks(read(FIRST * 2), samples)

	local parts: { string } = {}
	for index: number, name: string in ORDER do
		local low: number = index * FIRST * MILLISECONDS
		local high: number = low * 2
		local times: { number }? = samples[`clock {name}Ms`]
		if times == nil or #times ~= 2 or times[1] ~= low or times[2] ~= high then
			return false, `The reads pushed clock {name}Ms as {table.concat(times or {}, ",")}, not {low},{high}`
		end

		table.insert(parts, string.format("%s %.3f/%.3f/%.3f", name, low, high, high))
	end

	local head: string = `{LABEL} relay clocks, ms p50/p95/p99 over the reads`
	local across: string = "delivery and back across a worker's clock and the main thread's"
	local expected: string = `{head}, {across}: {table.concat(parts, "; ")}`
	local line: string? = Run.clocksLine(LABEL, samples)
	if line ~= expected then
		return false, `The clocks line read:\n{line}\nnot:\n{expected}`
	end

	-- 2) Reads with no relayClocks, beside a figure of their own: nothing pushed, and no line
	local plain: { [string]: { number } } = { viewerBytes = { 1000 } }
	for _ = 1, 2 do
		Run.clocks({ ticks = 20, relaySkipped = 0, stages = {} }, plain)
	end

	local pushed: { string } = {}
	for name: string in plain do
		if name ~= "viewerBytes" then
			table.insert(pushed, name)
		end
	end

	if #pushed > 0 then
		return false, `Reads with no relayClocks pushed {table.concat(pushed, ", ")}`
	elseif Run.clocksLine(LABEL, plain) ~= nil then
		return false, "Reads with no relayClocks gave a clocks line"
	end

	return true, nil
end
