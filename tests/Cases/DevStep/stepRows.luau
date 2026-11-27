--[[
    Step 3's rows in the step table: Tread's time on each of the tick's
    first three places, the send time at three places, and the split's and
    the frame caps' counts, each quiet row gone while both halves read 0
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local HALVES: { string } = { "before", "after" }

-- A before half with the caps off and an after half with them on, each carrying step 3's figures alone
local BEFORE: { [string]: number } = {
	place1P50 = 12.5,
	place1P95 = 14,
	place2P50 = 4,
	place2P95 = 5.5,
	place3P50 = 2,
	place3P95 = 2.25,
	relaySend = 20,
	deferred = 0,
	fallbacks = 0,
	npcsWaited = 0,
	antiEspCut = 4,
	relayLeft = 0,
	relayOver = 0,
	farHalved = 0,
}

local AFTER: { [string]: number } = {
	place1P50 = 8,
	place1P95 = 9.5,
	place2P50 = 6.5,
	place2P95 = 7,
	place3P50 = 2,
	place3P95 = 2.5,
	relaySend = 36.5,
	deferred = 950,
	fallbacks = 3,
	npcsWaited = 25,
	antiEspCut = 0,
	relayLeft = 125,
	relayOver = 0,
	farHalved = 40,
}

-- Worked by hand: the change is after less before at the row's places, and the percent that change over before, each
-- of a pair's p50 and p95 in turn. The runs over the budget read 0 in both halves and are left out
local TABLE: { string } = {
	"S4 table, figure: before after change percent",
	"Tread ms on the tick's Heartbeat p50/p95: 12.500/14.000 8.000/9.500 -4.500/-4.500 -36.0%/-32.1%",
	"Tread ms on the one after p50/p95: 4.000/5.500 6.500/7.000 +2.500/+1.500 +62.5%/+27.3%",
	"Tread ms on the one after that p50/p95: 2.000/2.250 2.000/2.500 +0.000/+0.250 +0.0%/+11.1%",
	"send ms, decode to blocks out p50: 20.000 36.500 +16.500 +82.5%",
	"ticks deferred: 0 950 +950 n/a",
	"split fallbacks: 0 3 +3 n/a",
	"NPC steps made to wait: 0 25 +25 n/a",
	"antiEsp slices cut at the deadline: 4 0 -4 -100.0%",
	"viewer turns relay.budget left: 0 125 +125 n/a",
	"relay runs with the far band halved: 0 40 +40 n/a",
}

-- The quiet rows' labels, each left out when both halves read 0
local QUIET: { string } = {
	"ticks deferred",
	"split fallbacks",
	"NPC steps made to wait",
	"antiEsp slices cut",
	"viewer turns relay.budget left",
	"relay runs over relay.budget",
	"relay runs with the far band halved",
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) The rows in the table's order, word for word
	local text: string = Compare.table("S4", HALVES, BEFORE, AFTER)
	local expected: string = table.concat(TABLE, "\n")
	if text ~= expected then
		return false, `The table read:\n{text}\nnot:\n{expected}`
	end

	-- 2) Every quiet row leaves with both halves at 0, and the place rows and the send row stay at 0
	local still: { [string]: number } = table.clone(BEFORE)
	for name: string in still do
		still[name] = 0
	end

	local quiet: string = Compare.table("S4", HALVES, still, still)
	for _, label: string in QUIET do
		if string.find(quiet, `\n{label}`, 1, true) then
			return false, `With both halves at 0, the table kept its {label} row:\n{quiet}`
		end
	end

	if #string.split(quiet, "\n") ~= 5 then
		return false, `With both halves at 0, the table read:\n{quiet}`
	end

	return true, nil
end
