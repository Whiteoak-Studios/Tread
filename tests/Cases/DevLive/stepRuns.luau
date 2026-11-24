--[[
    The split, NPC budget and levers runs are scenarios the panel lists for
    their minutes outside Run all, saved as the other step runs are, and each
    whole report, its halves' long lines dropped, fits the size budget
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")
local Report = require("../../Fixtures/DevStep/Report")
local Step = require("../../Fixtures/DevStep/Step")

local LIVE: string = "dev/Server/Live.luau"
local STARTED: number = 1763500000 -- The os.time() a stand-in run started at
local BUDGET: number = 30000 -- Characters a step run's report stays under, as the step benchmark's case holds it
local KEPT_BYTES: number = 32000 -- What the server keeps of a run's Output, the live config's reportBytes

-- Each run: its name, the kind of step run its scenario runs, about how long it runs, how its header opens and its
-- tables' titles
type Listed = { name: string, kind: string, minutes: number, title: string, tables: { string } }

local RUNS: { Listed } = {
	{
		name = "BenchStepSplit",
		kind = "split",
		minutes = 7,
		title = "Step benchmark split run session 3, ",
		tables = { "S4", "Spread150", "Spread300" },
	},
	{
		name = "BenchStepNpcs",
		kind = "npcs",
		minutes = 2.5,
		title = "Step benchmark NPC budget run session 3, ",
		tables = { "S4Npcs" },
	},
	{
		name = "BenchStepLevers",
		kind = "levers",
		minutes = 7,
		title = "Step benchmark levers run session 3, ",
		tables = { "S4 crowdCap", "S4 antiEspWorkers", "Spread300 bands" },
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local config: any = loaded.require(server.Config.Live)
	local clocks: { string } =
		loaded.require(dataModel:GetService("ReplicatedStorage").Packages.Tread.Server.Relay).CLOCKS

	-- 1) Each listed at its minutes, out of Run all's queue, and its scenario a function that runs its kind
	local mounted: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		return true, "drove and cleaned up", { skipped = 1 }
	end)

	local scenarios: { [string]: any } = {
		BenchStepSplit = mounted.BenchStepSplit,
		BenchStepNpcs = mounted.BenchStepNpcs,
		BenchStepLevers = mounted.BenchStepLevers,
	}

	for _, run: Listed in RUNS do
		local listed: any = nil
		for _, entry: any in LiveRuns.runs do
			if entry.name == run.name then
				listed = entry
			end
		end

		if listed == nil or listed.minutes ~= run.minutes then
			return false, `The panel lists {run.name} as {listed and listed.minutes} minutes, not {run.minutes}`
		elseif table.find(LiveRuns.queue, run.name) then
			return false, `Run all's queue runs {run.name}`
		elseif type(scenarios[run.name]) ~= "function" then
			return false, `{run.name}'s module gives a {type(scenarios[run.name])}, not a scenario's function`
		end

		local before: number = #mounted.events
		local passed: boolean, reason: string? = scenarios[run.name]()
		local header: string = mounted.events[before + 1] or ""
		if not passed then
			return false, `{run.name} failed: {reason}`
		elseif string.find(header, run.title, 1, true) ~= 1 then
			return false, `{run.name} opened on:\n{header}`
		end
	end

	-- 2) Saved as single runs under their start and name, through a game whose DataStoreService keeps each key
	local written: { string } = {}
	local store: any = {
		GetDataStore = function (_: any, _: string): any
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
	local keys: { string } = {}
	for _, run: Listed in RUNS do
		Live.saveRun(STARTED, run.name, `{run.name}'s report`)
		table.insert(keys, `{STARTED}-{run.name}`)
	end

	if table.concat(written, ",") ~= table.concat(keys, ",") then
		return false, `The runs' reports were written under {table.concat(written, ",")}`
	end

	-- 3) Each whole report, with relay clocks and with none, under the budget and what the server keeps, its tables
	-- and the verdict there and its halves' summaries, relay clocks and modes dropped
	for _, run: Listed in RUNS do
		for _, variant: { kind: string, clocks: { string }? } in
			{
				{ kind = "with no relay clocks", clocks = nil },
				{ kind = "with relay clocks", clocks = clocks },
			}
		do
			local given: { string }? = variant.clocks
			local whole: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
				return true, "drove and cleaned up", Report.figures(given)
			end)

			whole.BenchStep(run.kind)

			local verdict: string = `Runner PASS {run.name}: passed`
			local report: any = LiveRuns.report(run.name, config.reportBytes, config.dropped)
			for _, event: string in whole.events do
				local half: string? = string.match(event, "^half (%S+)$")
				if half then
					for _, line: string in Report.half(half, given) do
						LiveRuns.collect(report, line)
					end
				else
					LiveRuns.collect(report, event)
				end
			end

			LiveRuns.collect(report, verdict)

			local text: string = LiveRuns.text(report)
			local characters: number = utf8.len(text) or #text
			local named: string = `{run.name}'s report {variant.kind}`
			if report.full or config.reportBytes ~= KEPT_BYTES or #text >= KEPT_BYTES then
				return false, `{named} is {#text} B, past the {KEPT_BYTES} B the server keeps`
			elseif characters >= BUDGET then
				return false, `{named} is {characters} characters, past the budget's {BUDGET}`
			elseif string.find(text, " summary over ", 1, true) or string.find(text, " relay clocks, ", 1, true) then
				return false, `{named} kept a half's summary or relay clocks`
			elseif string.find(text, "seed 1 mode: ", 1, true) then
				return false, `{named} kept a half's mode`
			elseif string.sub(text, -#verdict) ~= verdict then
				return false, `{named} does not end with the Runner's verdict`
			end

			for _, title: string in run.tables do
				if not string.find(text, `\n{title} table, figure: before after change percent\n`, 1, true) then
					return false, `{named} has no {title} table`
				end
			end
		end
	end

	return true, nil
end
