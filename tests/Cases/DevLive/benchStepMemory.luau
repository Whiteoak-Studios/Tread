--[[
    The verdict memory run is a scenario the panel lists at about 2.5 minutes
    outside Run all, saved as the other step runs are, and its whole report,
    its halves' long lines dropped, fits the size budget with its rows
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")
local Report = require("../../Fixtures/DevStep/Report")
local Step = require("../../Fixtures/DevStep/Step")

local NAME: string = "BenchStepMemory"
local LIVE: string = "dev/Server/Live.luau"
local SCENARIO: string = "dev/Server/Scenarios/BenchStepMemory.luau"
local MINUTES: number = 2.5 -- About how long it runs
local STARTED: number = 1763500000 -- The os.time() a stand-in run started at
local BUDGET: number = 30000 -- Characters a step run's report stays under, as the step benchmark's case holds it
local VERDICT: string = "Runner PASS BenchStepMemory: passed"

-- The two rows verdict memory's figures print, which the report must keep
local ROWS: { string } = {
	"\nantiEsp tests answered from memory a tick p50: 0.0 31950.5 +31950.5 n/a\n",
	"\nantiEsp rays a kept box blocked a tick p50: 0.0 191700.5 +191700.5 n/a\n",
}

-- A half's figures the size a live half's lines give them, verdict memory's at the most digits a 149-bot after half
-- could print: about 639,000 tests due a second over 20 ticks, each of up to six rays a kept box could block
local function figures(clocks: { string }?, half: string?): { [string]: number }
	local given: { [string]: number } = Report.figures(clocks)
	given.antiEspKept, given.antiEspBoxRays = 0, 0
	if half == "after" then
		given.antiEspKept, given.antiEspBoxRays = 31950.5, 191700.5
	end

	return given
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local config: any = loaded.require(server.Config.Live)

	-- 1) Listed for the panel at about 2.5 minutes, out of Run all's queue, and a scenario's function once loaded
	local listed: any = nil
	for _, run: any in LiveRuns.runs do
		if run.name == NAME then
			listed = run
		end
	end

	local stands: { [any]: any } = {
		[server.Scenarios.BenchStep] = function () end,
		[server.Game] = {},
	}

	local scenario: any =
		Kit.loader(dataModel, { [server.Scenarios[NAME]] = SCENARIO }, stands, loaded.require)(server.Scenarios[NAME])

	if listed == nil or listed.minutes ~= MINUTES then
		return false, `The panel lists {NAME} as {listed and listed.minutes} minutes, not {MINUTES}`
	elseif table.find(LiveRuns.queue, NAME) then
		return false, `Run all's queue runs {NAME}`
	elseif type(scenario) ~= "function" then
		return false, `{NAME}'s module gives a {type(scenario)}, not a scenario's function`
	end

	-- 2) Saved as a single run under its start and its name, through a game whose DataStoreService keeps each key
	local written: { string } = {}
	local opened: { string } = {}
	local store: any = {
		GetDataStore = function (_: any, name: string): any
			table.insert(opened, name)

			return {
				SetAsync = function (_: any, key: string, _: any)
					table.insert(written, key)
				end,
			}
		end,
	}

	local place: any = {
		GetService = function (_: any, name: string): any
			if name == "DataStoreService" then
				return store
			end

			return dataModel:GetService(name)
		end,
	}

	local results: { [any]: any } = {
		[shared.Network.Server] = {},
		[server.BotPanel] = {},
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(place, { [server.Live] = LIVE }, results, loaded.require)(server.Live)
	Live.saveRun(STARTED, NAME, `{NAME}'s report`)

	if table.concat(written, ",") ~= `{STARTED}-{NAME}` or table.concat(opened, ",") ~= "LiveRuns" then
		return false, `{NAME}'s report was written under {table.concat(written, ",")} in {table.concat(opened, ",")}`
	end

	-- 3) A whole memory run's report, with relay clocks and with none, under the budget, its table, both rows and the
	-- verdict there, and its halves' summaries, relay clocks and modes dropped
	local clocksLoaded: Harness.Loaded = Harness.load()
	local packages: any = clocksLoaded.game:GetService("ReplicatedStorage").Packages
	local clocks: { string } = clocksLoaded.require(packages.Tread.Server.Relay).CLOCKS

	local variants: { { kind: string, clocks: { string }? } } = {
		{ kind = "with no relay clocks", clocks = nil },
		{ kind = "with relay clocks", clocks = clocks },
	}

	for _, variant: { kind: string, clocks: { string }? } in variants do
		local given: { string }? = variant.clocks
		local kind: string = variant.kind
		local mounted: Step.Mounted = Step.load(function (_: string, half: string?): (boolean, string, any)
			return true, "drove and cleaned up", figures(given, half)
		end)

		local passed: boolean, reason: string? = mounted.BenchStep("memory")
		if not passed then
			return false, `The memory run {kind} failed: {reason}`
		end

		local report: any = LiveRuns.report(NAME, config.reportBytes, config.dropped)
		for _, event: string in mounted.events do
			local run: string? = string.match(event, "^half (%S+)$")
			if run then
				for _, line: string in Report.half(run, given) do
					LiveRuns.collect(report, line)
				end
			else
				LiveRuns.collect(report, event)
			end
		end

		LiveRuns.collect(report, VERDICT)

		local text: string = LiveRuns.text(report)
		local characters: number = utf8.len(text) or #text
		if report.full then
			return false, `The memory run's report {kind} passed its {config.reportBytes} B and was cut`
		elseif characters >= BUDGET then
			return false, `The memory run's report {kind} is {characters} characters, past the budget's {BUDGET}`
		elseif string.find(text, " summary over ", 1, true) or string.find(text, " relay clocks, ", 1, true) then
			return false, `The memory run's report {kind} kept a half's summary or relay clocks`
		elseif string.find(text, "seed 1 mode: ", 1, true) then
			return false, `The memory run's report {kind} kept a half's mode`
		elseif not string.find(text, "\nRooms150 table, figure: before after change percent\n", 1, true) then
			return false, `The memory run's report {kind} has no table of its load`
		elseif string.sub(text, -#VERDICT) ~= VERDICT then
			return false, `The memory run's report {kind} does not end with the Runner's verdict`
		end

		for _, row: string in ROWS do
			if not string.find(text, row, 1, true) then
				return false, `The memory run's report {kind} has no row {row}`
			end
		end
	end

	return true, nil
end
