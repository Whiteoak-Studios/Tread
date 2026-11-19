--[[
    The step benchmark and its noise run are scenarios the panel lists
    outside Run all, saved as single runs while one off the list is not, and
    a whole report, its halves' long lines dropped, fits the panel's limits
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementMethod

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")
local Report = require("../../Fixtures/DevStep/Report")
local Step = require("../../Fixtures/DevStep/Step")

local LIVE: string = "dev/Server/Live.luau"
local RUNS: { string } = { "BenchStep", "BenchStepNoise" }
local MINUTES: number = 7 -- About how long each runs
local STARTED: number = 1763500000 -- The os.time() a stand-in run started at
local PANEL: number = 16384 -- The characters past which the panel's report is not yet known to copy whole
local VERDICT: string = "Runner PASS BenchStep: passed"

-- Each key a stand-in DataStore was written under, and each DataStore opened, by its name
local Written: { string } = {}
local Opened: { string } = {}

-- Lune's DataStoreService opens nothing, so it hands out a stand-in that keeps each key it is written under
pcall(roblox.implementMethod, "DataStoreService", "GetDataStore", function (_: any, name: string): any
	table.insert(Opened, name)

	return {
		SetAsync = function (_: any, key: string, _: any)
			table.insert(Written, key)
		end,
	}
end)

-- Other runs' summaries, relay clocks and modes and a step half's other lines, which every report keeps
local KEPT: { string } = {
	"Bots S4/workers seed 1 summary over 119 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S3/serial seed 1 summary over 119 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S4 seed 2 summary over 119 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S3@500 seed 1 summary over 59 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S4/workers seed 1 mode: 4 relay workers started, on for this load; views 1 in process, 37/37/38/37",
	"Bots Spread150/serial seed 1 mode: 4 relay workers started, off for this load; views 150 in process",
	"Bots S4/workers seed 1 relay clocks, ms p50/p95/p99 over the reads: head 0.123/0.456/0.789",
	"Bots S4 seed 1 relay clocks, ms p50/p95/p99 over the reads: head 0.123/0.456/0.789",
	"Bots S4/before seed 1 group fight: 149 bots, its summary over 49 reads to come",
	"Bots S4/before seed 1 server: 59.97 Heartbeats a second",
}

-- The per-second lines, and a step half's summary, relay clocks and mode, which every report drops
local DROPPED: { string } = {
	"Bots S4/before seed 1 second 3: real players 1, viewers {}, stats {}",
	"Bots Spread150/after seed 1 summary over 49 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots Spread300/first seed 1 summary over 49 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S4/second seed 1 summary over 49 reads, p50/p95/p99: ticks 20.000/21.000/21.000",
	"Bots S4/before seed 1 relay clocks, ms p50/p95/p99 over the reads: head 0.123/0.456/0.789",
	"Bots Spread300/second seed 1 relay clocks, ms p50/p95/p99 over the reads: head 0.123/0.456/0.789",
	"Bots Spread150/after seed 1 mode: 4 relay workers started, on for this load; views 1 in process",
	"Bots S4/first seed 1 mode: 4 relay workers started, on for this load; views 1 in process",
}

--[[
    A whole step benchmark report as the panel keeps it: the run with each
    half answering with figures the live half's size, every half's lines
    put where the run asked for it, then the Runner's verdict
--]]

local function wholeReport(clocks: { string }?): (string, any)
	local mounted: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		return true, "drove and cleaned up", Report.figures(clocks)
	end)

	mounted.BenchStep()

	local loaded: Harness.Loaded = Harness.load()
	local config: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Config.Live)
	local LiveRuns: any = loaded.require(loaded.game:GetService("ReplicatedStorage").Shared.Dev.LiveRuns)
	local report: any = LiveRuns.report("BenchStep", config.reportBytes, config.dropped)

	for _, event: string in mounted.events do
		local run: string? = string.match(event, "^half (%S+)$")
		if run then
			for _, line: string in Report.half(run, clocks) do
				LiveRuns.collect(report, line)
			end
		else
			LiveRuns.collect(report, event)
		end
	end

	LiveRuns.collect(report, VERDICT)

	return LiveRuns.text(report), report
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local config: any = loaded.require(server.Config.Live)

	-- 1) Both are listed for the panel at about 7 minutes, neither is in Run all's queue, and each loads as a scenario
	local mounted: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		return true, "drove and cleaned up", nil
	end)

	local scenarios: { [string]: any } = { BenchStep = mounted.BenchStep, BenchStepNoise = mounted.BenchStepNoise }

	for _, name: string in RUNS do
		local listed: any = nil
		for _, run: any in LiveRuns.runs do
			if run.name == name then
				listed = run
			end
		end

		if listed == nil or listed.minutes ~= MINUTES then
			return false, `The panel lists {name} as {listed and listed.minutes} minutes, not {MINUTES}`
		elseif table.find(LiveRuns.queue, name) then
			return false, `Run all's queue runs {name}`
		elseif type(scenarios[name]) ~= "function" then
			return false, `{name}'s module gives a {type(scenarios[name])}, not a scenario's function`
		end
	end

	-- 2) A single run on the save list is saved under its start and name, and one off it opens no DataStore at all
	local results: { [any]: any } = {
		[shared.Network.Server] = {},
		[server.BotPanel] = {},
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(dataModel, { [server.Live] = LIVE }, results, loaded.require)(server.Live)
	table.clear(Written)
	table.clear(Opened)

	Live.saveRun(STARTED, "BenchS4", "BenchS4's report")
	if #Opened > 0 or #Written > 0 then
		return false, `A run off the save list opened {#Opened} DataStores and wrote {#Written} keys`
	end

	for _, name: string in RUNS do
		Live.saveRun(STARTED, name, `{name}'s report`)
	end

	local keys: string = table.concat(Written, ",")
	if keys ~= `{STARTED}-BenchStep,{STARTED}-BenchStepNoise` or table.concat(Opened, ",") ~= "LiveRuns,LiveRuns" then
		return false, `The save list's runs were written under {keys} in {table.concat(Opened, ",")}`
	end

	-- 3) The drop leaves out the halves' summaries and the per-second lines, and every other run's lines are kept
	local mixed: any = LiveRuns.report("BenchWorkers", config.reportBytes, config.dropped)
	for _, line: string in DROPPED do
		LiveRuns.collect(mixed, line)
	end

	for _, line: string in KEPT do
		LiveRuns.collect(mixed, line)
	end

	if LiveRuns.text(mixed) ~= table.concat(KEPT, "\n") then
		return false, `The report kept:\n{LiveRuns.text(mixed)}`
	end

	-- 4) A whole report of three loads, both halves and their tables, under the panel's limit with no relay clocks,
	-- and with every section of them still kept whole, its tables and the verdict all there
	local loadedClocks: Harness.Loaded = Harness.load()
	local packages: any = loadedClocks.game:GetService("ReplicatedStorage").Packages
	local clocks: { string } = loadedClocks.require(packages.Tread.Server.Relay).CLOCKS

	local variants: { { kind: string, clocks: { string }? } } = {
		{ kind = "with no relay clocks", clocks = nil },
		{ kind = "with relay clocks", clocks = clocks },
	}

	for _, variant: { kind: string, clocks: { string }? } in variants do
		local given: { string }? = variant.clocks
		local kind: string = variant.kind
		local text: string, report: any = wholeReport(given)
		local characters: number = utf8.len(text) or #text

		if report.full then
			return false, `The step benchmark's report {kind} passed its {config.reportBytes} B and was cut`
		elseif given == nil and characters >= PANEL then
			return false, `The step benchmark's report {kind} is {characters} characters, past the panel's {PANEL}`
		elseif string.find(text, " summary over ", 1, true) or string.find(text, " relay clocks, ", 1, true) then
			return false, `The step benchmark's report {kind} kept a half's summary or relay clocks`
		elseif string.find(text, "seed 1 mode: ", 1, true) then
			return false, `The step benchmark's report {kind} kept a half's mode`
		elseif string.sub(text, -#VERDICT) ~= VERDICT then
			return false, `The step benchmark's report {kind} does not end with the Runner's verdict`
		end

		for _, head: string in { "S4 table, ", "Spread150 table, ", "Spread300 table, " } do
			if not string.find(text, `\n{head}`, 1, true) then
				return false, `The step benchmark's report {kind} has no {head}line`
			end
		end

		if given and not string.find(text, "\nclock back ms p50/p95: ", 1, true) then
			return false, `The step benchmark's report {kind} has no row for its last clock`
		end
	end

	return true, nil
end
