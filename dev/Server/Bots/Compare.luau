--[[
    The step benchmark's closing table for one load: each figure its two
    halves carry side by side, with the change from the first to the second
    and that change as a percent of the first, a row a line
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Relay = require(Packages.Tread.Server.Relay)

local TICK_STAGES: { string } = require(ServerScriptService.Server.Bots.Config).tick.stages
local BESIDE: string = require(ServerScriptService.Server.Bots.Config).tick.beside
local FPS: number = require(ServerScriptService.Server.Bots.Config).fps
local DRIFT: number = require(ServerScriptService.Server.Bots.Config).step.drift
local PERCENT: number = 100 -- Turns a share into a percent
local TIME: number = 3 -- Decimal places a time in milliseconds or microseconds prints with
local RATE: number = 2 -- A rate a second's
local STUDS: number = 2 -- A distance's
local COUNT: number = 1 -- A count a relay run's or a tick's
local WHOLE: number = 0 -- A whole count's
local QUIET_STAGE: string = "npcs" -- The stage only a load with NPCs runs, which reads 0 in every other
local PERCENT_FORMAT: string = "%+.1f%%"
local MISSING: string = "missing" -- A half's column when the half or its figure is missing
local NONE: string = "n/a" -- A change or a percent with nothing to work it out from
local COLUMN: string = " " -- Between a row's columns
local PAIR: string = "/" -- Between a row's p50 and p95 in each column
local NEWLINE: string = "\n" -- Between the table's rows

-- Each figure a half's lines carry, by the name the bot harness's run gives it
export type Figures = { [string]: number }

-- A row: its figures' names, a p50 and p95 pair or one alone, what the table calls it, its decimal places, whether
-- the halves' drift flags it, and whether it leaves the table when every figure reads 0 in both halves
type Row = { names: { string }, label: string, places: number, drift: boolean?, quiet: boolean? }

-- The rows before the tick's stages, in the table's order
local HEAD: { Row } = {
	{ names = { "calibration" }, label = "calibration loop µs p50", places = TIME, drift = true },
	{ names = { "playerFrom" }, label = "real player studs from the load's point", places = STUDS },
	{ names = { "playerMoved" }, label = "real player studs walked", places = STUDS },
	{ names = { "heartbeats" }, label = "Heartbeats a second", places = RATE },
	{ names = { "fps" }, label = `server FPS p{math.round(FPS * PERCENT)}`, places = RATE },
	{ names = { "frameP50", "frameP95" }, label = "frame ms p50/p95", places = TIME },
	{ names = { "treadP50", "treadP95" }, label = "Tread ms, heaviest Heartbeat p50/p95", places = TIME },
	{ names = { "botsP50", "botsP95" }, label = "bots' stage ms there p50/p95", places = TIME, quiet = true },
	{ names = { "place1P50", "place1P95" }, label = "Tread ms on the tick's Heartbeat p50/p95", places = TIME },
	{ names = { "place2P50", "place2P95" }, label = "Tread ms on the one after p50/p95", places = TIME },
	{ names = { "place3P50", "place3P95" }, label = "Tread ms on the one after that p50/p95", places = TIME },
	{ names = { "tickFrameP50", "tickFrameP95" }, label = "frame ms holding a tick p50/p95", places = TIME },
	{ names = { "tickP50", "tickP95" }, label = "tick total ms p50/p95", places = TIME },
}

-- The rows after the tick's stages and before the relay's clocks
local TAIL: { Row } = {
	{ names = { "finish" }, label = "finish ms p50", places = TIME },
	{ names = { "relaySend" }, label = "send ms, decode to blocks out p50", places = TIME },
	{ names = { BESIDE }, label = `{BESIDE} ms p95`, places = TIME },
	{ names = { "antiEspTests" }, label = `{BESIDE} tests a tick p50`, places = COUNT },
	{ names = { "antiEspRays" }, label = `{BESIDE} rays a tick p50`, places = COUNT },
	{
		names = { "antiEspKept" },
		label = `{BESIDE} tests answered from memory a tick p50`,
		places = COUNT,
		quiet = true,
	},
	{
		names = { "antiEspBoxRays" },
		label = `{BESIDE} rays a kept box blocked a tick p50`,
		places = COUNT,
		quiet = true,
	},
	{ names = { "antiEspHidden" }, label = `{BESIDE} hidden results`, places = WHOLE },
	{ names = { "antiEspFailOpens" }, label = `{BESIDE} fail-opens`, places = WHOLE },
	{ names = { "antiEspWorkerTests" }, label = `{BESIDE} tests on workers`, places = WHOLE, quiet = true },
	{ names = { "antiEspWorkerBusy" }, label = `{BESIDE} workers busy ms a second p50`, places = TIME, quiet = true },
	{ names = { "antiEspWorkerLongest" }, label = `{BESIDE} longest batch ms p95`, places = TIME, quiet = true },
	{ names = { "antiEspLateBatches" }, label = `{BESIDE} batches late`, places = WHOLE, quiet = true },
	{ names = { "dropped" }, label = "ticks dropped", places = WHOLE, quiet = true },
	{ names = { "relaySkipped" }, label = "relay runs skipped", places = WHOLE, quiet = true },
	{ names = { "deferred" }, label = "ticks deferred", places = WHOLE, quiet = true },
	{ names = { "fallbacks" }, label = "split fallbacks", places = WHOLE, quiet = true },
	{ names = { "npcsWaited" }, label = "NPC steps made to wait", places = WHOLE, quiet = true },
	{ names = { "antiEspCut" }, label = `{BESIDE} slices cut at the deadline`, places = WHOLE, quiet = true },
	{ names = { "relayLeft" }, label = "viewer turns relay.budget left", places = WHOLE, quiet = true },
	{ names = { "relayOver" }, label = "relay runs over relay.budget", places = WHOLE, quiet = true },
	{ names = { "farHalved" }, label = "relay runs with the far band halved", places = WHOLE, quiet = true },
	{ names = { "records" }, label = "records a relay run p50", places = COUNT },
	{ names = { "recordsCut" }, label = "records cut a relay run p50", places = COUNT },
	{
		names = { "crowdRest" },
		label = "viewer-player pairs past the crowd cap a relay run p50",
		places = COUNT,
		quiet = true,
	},
	{ names = { "bytes" }, label = "bytes a relay run p50", places = COUNT },
	{ names = { "viewerP50", "viewerP95" }, label = "viewer B a second p50/p95", places = WHOLE },
	{ names = { "ownerFull" }, label = "OwnerStates in full", places = WHOLE },
	{ names = { "ownerAcks" }, label = "OwnerStates as acknowledgments", places = WHOLE },
	{ names = { "ownerChecked" }, label = "OwnerState checks compared", places = WHOLE },
	{ names = { "ownerMismatches" }, label = "OwnerState checks missed", places = WHOLE },
	{ names = { "skipped" }, label = "commands lazy decode skipped", places = WHOLE },
}

local Compare = {}

-- Every row in the table's order: the head, each tick stage at p50, the tail, then each relay clock at p50 and p95
local function rows(): { Row }
	local all: { Row } = table.clone(HEAD)

	for _, stage: string in TICK_STAGES do
		table.insert(all, { names = { stage }, label = `{stage} ms p50`, places = TIME, quiet = stage == QUIET_STAGE })
	end

	table.move(TAIL, 1, #TAIL, #all + 1, all)

	for _, clock: string in Relay.CLOCKS do
		local names: { string } = { `clock {clock} p50`, `clock {clock} p95` }
		table.insert(all, { names = names, label = `clock {clock} ms p50/p95`, places = TIME })
	end

	return all
end

-- A half's column: each of the row's figures at its places, missing for one it lacks, or missing for no half at all
local function shown(row: Row, half: Figures?): string
	if half == nil then
		return MISSING
	end

	local values: { string } = {}
	for _, name: string in row.names do
		local value: number? = half[name]
		table.insert(values, value and string.format(`%.{row.places}f`, value) or MISSING)
	end

	return table.concat(values, PAIR)
end

-- The change column and the percent column: each figure's change and that change over the first, where both have it
local function changed(row: Row, first: Figures, second: Figures): (string, string)
	local changes: { string } = {}
	local percents: { string } = {}

	for _, name: string in row.names do
		local before: number?, after: number? = first[name], second[name]
		local change: string, percent: string = NONE, NONE

		if before and after then
			change = string.format(`%+.{row.places}f`, after - before)

			if before ~= 0 then
				percent = string.format(PERCENT_FORMAT, (after - before) / before * PERCENT)
			end
		end

		table.insert(changes, change)
		table.insert(percents, percent)
	end

	return table.concat(changes, PAIR), table.concat(percents, PAIR)
end

--[[
    One row's line: its label, each half's column, the change from the
    first to the second and that change as a percent of the first, flagged
    on a row that takes it when the halves differ by more than the drift
    share. Nil when neither half has any of the row's figures, and for a
    quiet row when both halves read 0 in every one of them
--]]

local function rowLine(row: Row, first: Figures?, second: Figures?): string?
	local carried: boolean = false
	local zero: boolean = first ~= nil and second ~= nil
	for _, name: string in row.names do
		if (first and first[name]) ~= nil or (second and second[name]) ~= nil then
			carried = true
		end

		if (first and first[name]) ~= 0 or (second and second[name]) ~= 0 then
			zero = false
		end
	end

	if not carried or (row.quiet and zero) then
		return nil
	end

	local change: string, percent: string = NONE, NONE
	local flag: string = ""

	if first and second then
		change, percent = changed(row, first, second)

		local before: number?, after: number? = first[row.names[1]], second[row.names[1]]
		if row.drift and before and after and math.abs(after - before) > DRIFT * before then
			flag = `{COLUMN}drift past {DRIFT * PERCENT}%`
		end
	end

	local columns: { string } = { shown(row, first), shown(row, second), change, percent }

	return `{row.label}: {table.concat(columns, COLUMN)}{flag}`
end

--[[
    The closing table of one load's two halves, named in the order of their
    columns: a head line naming the columns, then a row for each figure
    either half carries. A half that failed is given as nil, and its column
    reads missing in every row
--]]

function Compare.table(load: string, names: { string }, first: Figures?, second: Figures?): string
	local columns: { string } = { names[1], names[2], "change", "percent" }
	local lines: { string } = { `{load} table, figure: {table.concat(columns, COLUMN)}` }

	for _, row: Row in rows() do
		local line: string? = rowLine(row, first, second)
		if line then
			table.insert(lines, line)
		end
	end

	return table.concat(lines, NEWLINE)
end

return Compare
