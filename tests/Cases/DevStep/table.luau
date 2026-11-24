--[[
    The step benchmark's table gives fixed records fixed text: each row's
    halves, change and percent, a missing half reading missing, the drift
    flag past 5% only, no row neither half carries, nor a quiet one at 0 in both
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local HALVES: { string } = { "before", "after" }

-- The before half: the calibration at 20 µs, a figure for every row but the OwnerStates', and one relay clock
local BEFORE: { [string]: number } = {
	calibration = 20,
	playerFrom = 2.5,
	playerMoved = 30,
	heartbeats = 60,
	fps = 55.5,
	frameP50 = 16.5,
	frameP95 = 19.25,
	treadP50 = 12.5,
	treadP95 = 14,
	botsP50 = 0.5,
	botsP95 = 0.75,
	tickFrameP50 = 16.75,
	tickFrameP95 = 25,
	tickP50 = 12,
	tickP95 = 14,
	decode = 0.5,
	simulate = 4,
	npcs = 0,
	history = 0.25,
	relay = 6,
	finish = 2,
	antiEsp = 2,
	antiEspTests = 400,
	antiEspRays = 1500,
	antiEspHidden = 1000,
	antiEspFailOpens = 0,
	antiEspWorkerTests = 0,
	antiEspWorkerBusy = 0,
	antiEspWorkerLongest = 0,
	antiEspLateBatches = 0,
	dropped = 0,
	relaySkipped = 3,
	records = 1400,
	recordsCut = 0,
	crowdRest = 0,
	bytes = 20000,
	viewerP50 = 5000,
	viewerP95 = 6000,
	skipped = 0,
	["clock head p50"] = 0.125,
	["clock head p95"] = 0.25,
}

-- The after half: the calibration at 21 µs, exactly 5% past the before's, the NPCs' stage at 0 in both, and anti-ESP's
-- workers and the crowd cap working where the before half's read 0
local AFTER: { [string]: number } = {
	calibration = 21,
	playerFrom = 40,
	playerMoved = 0,
	heartbeats = 59.5,
	fps = 57,
	frameP50 = 16.5,
	frameP95 = 18.5,
	treadP50 = 10,
	treadP95 = 11.5,
	botsP50 = 0.5,
	botsP95 = 1,
	tickFrameP50 = 16.5,
	tickFrameP95 = 20,
	tickP50 = 9,
	tickP95 = 11,
	decode = 0.25,
	simulate = 4,
	npcs = 0,
	history = 0.25,
	relay = 4.5,
	finish = 2.5,
	antiEsp = 2,
	antiEspTests = 300,
	antiEspRays = 1200,
	antiEspHidden = 1500,
	antiEspFailOpens = 2,
	antiEspWorkerTests = 18000,
	antiEspWorkerBusy = 4.25,
	antiEspWorkerLongest = 0.875,
	antiEspLateBatches = 3,
	dropped = 2,
	relaySkipped = 0,
	records = 1400,
	recordsCut = 12.5,
	crowdRest = 52000,
	bytes = 19000,
	viewerP50 = 5000,
	viewerP95 = 6600,
	skipped = 9000,
	["clock head p50"] = 0.125,
	["clock head p95"] = 0.5,
}

-- Worked by hand: the change is after less before at the row's places, and the percent that change over before,
-- each of a pair's p50 and p95 in turn. The NPCs' row, quiet, reads 0 in both halves and is left out
local TABLE: { string } = {
	"S4 table, figure: before after change percent",
	"calibration loop µs p50: 20.000 21.000 +1.000 +5.0%",
	"real player studs from the load's point: 2.50 40.00 +37.50 +1500.0%",
	"real player studs walked: 30.00 0.00 -30.00 -100.0%",
	"Heartbeats a second: 60.00 59.50 -0.50 -0.8%",
	"server FPS p10: 55.50 57.00 +1.50 +2.7%",
	"frame ms p50/p95: 16.500/19.250 16.500/18.500 +0.000/-0.750 +0.0%/-3.9%",
	"Tread ms, heaviest Heartbeat p50/p95: 12.500/14.000 10.000/11.500 -2.500/-2.500 -20.0%/-17.9%",
	"bots' stage ms there p50/p95: 0.500/0.750 0.500/1.000 +0.000/+0.250 +0.0%/+33.3%",
	"frame ms holding a tick p50/p95: 16.750/25.000 16.500/20.000 -0.250/-5.000 -1.5%/-20.0%",
	"tick total ms p50/p95: 12.000/14.000 9.000/11.000 -3.000/-3.000 -25.0%/-21.4%",
	"decode ms p50: 0.500 0.250 -0.250 -50.0%",
	"simulate ms p50: 4.000 4.000 +0.000 +0.0%",
	"history ms p50: 0.250 0.250 +0.000 +0.0%",
	"relay ms p50: 6.000 4.500 -1.500 -25.0%",
	"finish ms p50: 2.000 2.500 +0.500 +25.0%",
	"antiEsp ms p95: 2.000 2.000 +0.000 +0.0%",
	"antiEsp tests a tick p50: 400.0 300.0 -100.0 -25.0%",
	"antiEsp rays a tick p50: 1500.0 1200.0 -300.0 -20.0%",
	"antiEsp hidden results: 1000 1500 +500 +50.0%",
	"antiEsp fail-opens: 0 2 +2 n/a",
	"antiEsp tests on workers: 0 18000 +18000 n/a",
	"antiEsp workers busy ms a second p50: 0.000 4.250 +4.250 n/a",
	"antiEsp longest batch ms p95: 0.000 0.875 +0.875 n/a",
	"antiEsp batches late: 0 3 +3 n/a",
	"ticks dropped: 0 2 +2 n/a",
	"relay runs skipped: 3 0 -3 -100.0%",
	"records a relay run p50: 1400.0 1400.0 +0.0 +0.0%",
	"records cut a relay run p50: 0.0 12.5 +12.5 n/a",
	"viewer-player pairs past the crowd cap a relay run p50: 0.0 52000.0 +52000.0 n/a",
	"bytes a relay run p50: 20000.0 19000.0 -1000.0 -5.0%",
	"viewer B a second p50/p95: 5000/6000 5000/6600 +0/+600 +0.0%/+10.0%",
	"commands lazy decode skipped: 0 9000 +9000 n/a",
	"clock head ms p50/p95: 0.125/0.250 0.125/0.500 +0.000/+0.250 +0.0%/+100.0%",
}

-- The quiet rows' labels, each left out when both halves read 0 in every figure it has
local QUIET: { string } = {
	"bots' stage ms there",
	"npcs ms p50",
	"antiEsp tests on workers",
	"antiEsp workers busy ms",
	"antiEsp longest batch",
	"antiEsp batches late",
	"ticks dropped",
	"relay runs skipped",
	"viewer-player pairs past",
}

-- The bots' stage's row with its p50 at 0 in both halves and its p95 at 0 before and 0.25 after
local QUIET_KEPT: string = "\nbots' stage ms there p50/p95: 0.000/0.000 0.000/0.250 +0.000/+0.250 n/a/n/a\n"

-- The OwnerState rows of a before half with checks off and an after half with them on, between the rows they
-- follow and lead, worked by hand as the whole table's are
local OWNER_FIGURES: { { name: string, before: number, after: number } } = {
	{ name = "ownerFull", before = 600, after = 30 },
	{ name = "ownerAcks", before = 0, after = 570 },
	{ name = "ownerChecked", before = 0, after = 600 },
	{ name = "ownerMismatches", before = 0, after = 30 },
}

local OWNER_ROWS: { string } = {
	"viewer B a second p50/p95: 5000/6000 5000/6600 +0/+600 +0.0%/+10.0%",
	"OwnerStates in full: 600 30 -570 -95.0%",
	"OwnerStates as acknowledgments: 0 570 +570 n/a",
	"OwnerState checks compared: 0 600 +600 n/a",
	"OwnerState checks missed: 0 30 +30 n/a",
	"commands lazy decode skipped: 0 9000 +9000 n/a",
}

-- The checks' rows with the after half failed
local FAILED_ROWS: { string } = {
	"OwnerState checks compared: 0 missing n/a n/a",
	"OwnerState checks missed: 0 missing n/a n/a",
}

-- Each calibration after a before of 20 µs, and whether the table flags the halves' drift: past 5% either way only
local DRIFTS: { { after: number, row: string } } = {
	{ after = 21.2, row = "calibration loop µs p50: 20.000 21.200 +1.200 +6.0% drift past 5%" },
	{ after = 18.9, row = "calibration loop µs p50: 20.000 18.900 -1.100 -5.5% drift past 5%" },
	{ after = 19, row = "calibration loop µs p50: 20.000 19.000 -1.000 -5.0%" },
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) The whole table, row for row, with no OwnerState rows since neither half carries them
	local text: string = Compare.table("S4", HALVES, BEFORE, AFTER)
	local expected: string = table.concat(TABLE, "\n")
	if text ~= expected then
		return false, `The table read:\n{text}\nnot:\n{expected}`
	end

	-- 2) A missing half: its column reads missing in every row, with no change or percent, the NPCs' row among them,
	-- since a quiet row leaves only when both halves read 0
	local rows: { string } = string.split(Compare.table("Spread150", HALVES, nil, AFTER), "\n")
	if #rows ~= #TABLE + 1 then
		return false, `With the before half missing the table has {#rows} lines, not {#TABLE + 1}`
	elseif not table.find(rows, "npcs ms p50: missing 0.000 n/a n/a") then
		return false, "With the before half missing, the NPCs' row was left out"
	end

	for index: number = 2, #rows do
		local row: string = rows[index]
		if not string.find(row, ": missing ", 1, true) or string.sub(row, -#" n/a n/a") ~= " n/a n/a" then
			return false, `With the before half missing, a row read {row}`
		end
	end

	if rows[2] ~= "calibration loop µs p50: missing 21.000 n/a n/a" then
		return false, `With the before half missing, the calibration read {rows[2]}`
	end

	-- 3) The drift flag past 5% either way, and none at 5%
	for _, drift: { after: number, row: string } in DRIFTS do
		local drifted: string = Compare.table("S4", HALVES, BEFORE, { calibration = drift.after })
		local calibrated: string = string.split(drifted, "\n")[2]
		if calibrated ~= drift.row then
			return false, `A calibration of {drift.after} after 20 read:\n{calibrated}\nnot:\n{drift.row}`
		end
	end

	-- 4) A figure one half carries prints the other as missing, and a clocks-off half's table has no clock rows
	local owned: { [string]: number } = table.clone(AFTER)
	owned.ownerFull = 600
	local owners: string = Compare.table("S4", HALVES, BEFORE, owned)
	if not string.find(owners, "\nOwnerStates in full: missing 600 n/a n/a\n", 1, true) then
		return false, `A figure only the after half carries read:\n{owners}`
	elseif string.find(owners, "acknowledgments", 1, true) or string.find(owners, "OwnerState checks", 1, true) then
		return false, "A figure neither half carries has a row"
	end

	local unclocked: { [string]: number } = table.clone(BEFORE)
	unclocked["clock head p50"] = nil
	unclocked["clock head p95"] = nil
	local clockless: string = Compare.table("S4", { "first", "second" }, unclocked, unclocked)
	if string.find(clockless, "clock", 1, true) then
		return false, `A table of clocks-off halves read:\n{clockless}`
	elseif string.split(clockless, "\n")[1] ~= "S4 table, figure: first second change percent" then
		return false, `The noise run's table opened with {string.split(clockless, "\n")[1]}`
	end

	-- 5) The OwnerState rows in order after the viewer's bytes, the checks' two last, and a failed half missing in each
	local checkedBefore: { [string]: number } = table.clone(BEFORE)
	local checkedAfter: { [string]: number } = table.clone(AFTER)
	for _, figure: { name: string, before: number, after: number } in OWNER_FIGURES do
		checkedBefore[figure.name] = figure.before
		checkedAfter[figure.name] = figure.after
	end

	local checked: string = Compare.table("S4", HALVES, checkedBefore, checkedAfter)
	local lines: number = #string.split(checked, "\n")
	if
		not string.find(checked, `\n{table.concat(OWNER_ROWS, "\n")}\n`, 1, true)
		or lines ~= #TABLE + #OWNER_FIGURES
	then
		return false, `With both halves' OwnerState figures, the table read:\n{checked}`
	end

	local failed: string = Compare.table("S4", HALVES, checkedBefore, nil)
	if not string.find(failed, `\n{table.concat(FAILED_ROWS, "\n")}\n`, 1, true) then
		return false, `With the after half failed, the table read:\n{failed}`
	end

	-- 6) Every quiet row at 0 in both halves leaves, and one figure of a pair past 0 in either half keeps its row
	local stillBefore: { [string]: number } = table.clone(BEFORE)
	local stillAfter: { [string]: number } = table.clone(AFTER)
	for _, still: { [string]: number } in { stillBefore, stillAfter } do
		still.botsP50, still.botsP95, still.dropped, still.relaySkipped = 0, 0, 0, 0
		still.antiEspWorkerTests, still.antiEspWorkerBusy, still.antiEspWorkerLongest = 0, 0, 0
		still.antiEspLateBatches, still.crowdRest = 0, 0
	end

	local quiet: string = Compare.table("S4", HALVES, stillBefore, stillAfter)
	for _, label: string in QUIET do
		if string.find(quiet, `\n{label}`, 1, true) then
			return false, `With both halves at 0, the table kept its {label} row:\n{quiet}`
		end
	end

	if #string.split(quiet, "\n") ~= #TABLE - #QUIET + 1 then
		return false, `With both halves at 0 in every quiet row, the table read:\n{quiet}`
	end

	stillAfter.botsP95 = 0.25
	local kept: string = Compare.table("S4", HALVES, stillBefore, stillAfter)
	if not string.find(kept, QUIET_KEPT, 1, true) then
		return false, `With the after half's bots' stage p95 past 0, the table read:\n{kept}`
	end

	return true, nil
end
