--[[
    The near rechecks' two rows: each read's change over its seconds and
    its gap in ms, at p50 in a window's figures, two quiet rows after the
    hidden results, and the window handing Run.near each read's seconds
--]]

--!strict
local fs = require("@lune/fs")

local Harness = require("../../Fixtures/DevServer/Harness")
local Window = require("../../Fixtures/DevStep/Window")

local RUN: string = "dev/Server/Bots/Run.luau"
local CALL: string = "\n%s*Run%.near%(([^%)]*)%)" -- A call of Run.near on a line of its own, its arguments captured
local ARGUMENTS: string = ", " -- Between a call's arguments
local SECONDS_AT: number = 4 -- Where among Run.near's arguments the read's seconds go
local HALVES: { string } = { "before", "after" }

-- Each read of the running totals and its seconds, from 100 rechecks and 3 s of gaps as the window opened: 48 with
-- 1.5 s of gaps over 1.5 s, none over 0.5 s, 16 with 1 s of gaps over 0.25 s, then 8 with 0.5 s of gaps in a read
-- with no seconds
type Read = { checks: number, seconds: number, readSeconds: number? }

local READS: { Read } = {
	{ checks = 148, seconds = 4.5, readSeconds = 1.5 },
	{ checks = 148, seconds = 4.5, readSeconds = 0.5 },
	{ checks = 164, seconds = 5.5, readSeconds = 0.25 },
	{ checks = 172, seconds = 6, readSeconds = nil },
}

-- Worked by hand: 48 / 1.5, 0 / 0.5 and 16 / 0.25 rechecks a second, and 1.5 s / 48, 1 s / 16 and 0.5 s / 8 in ms
local RECHECKS: string = "32,0,64"
local GAPS: string = "31.25,62.5,62.5"

-- The halves' figures for the rows, with the rays', hidden results' and fail-opens' rows around them
local BEFORE: { [string]: number } = {
	antiEspRays = 1500,
	antiEspHidden = 1000,
	antiEspNearRechecks = 600,
	antiEspNearGap = 33.5,
	antiEspFailOpens = 4,
}

local AFTER: { [string]: number } = {
	antiEspRays = 1200,
	antiEspHidden = 1500,
	antiEspNearRechecks = 1250.5,
	antiEspNearGap = 37.25,
	antiEspFailOpens = 6,
}

-- Worked by hand: each change after less before at the row's places, two for a rate a second and three for a time,
-- and that change as a percent of before
local TABLE: { string } = {
	"S3 table, figure: before after change percent",
	"antiEsp rays a tick p50: 1500.0 1200.0 -300.0 -20.0%",
	"antiEsp hidden results: 1000 1500 +500 +50.0%",
	"antiEsp near hidden rechecks a second p50: 600.00 1250.50 +650.50 +108.4%",
	"antiEsp near hidden recheck gap ms p50: 33.500 37.250 +3.750 +11.2%",
	"antiEsp fail-opens: 4 6 +2 +50.0%",
}

-- The rechecks' row with them at 0 before and 0.5 after, with no percent over a before of 0
local ALONE: string = "\nantiEsp near hidden rechecks a second p50: 0.00 0.50 +0.50 n/a\n"

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) Each read's rechecks over its seconds and, where it had any, their gap, every read kept as the last
	local last: any = { checks = 100, seconds = 3 }
	local rates: { [string]: { number } } = {}
	for _, read: Read in READS do
		Run.near(last, read.checks, read.seconds, read.readSeconds, rates)
	end

	local rechecks: string = table.concat(rates.antiEspNearRechecks or {}, ",")
	local gaps: string = table.concat(rates.antiEspNearGap or {}, ",")
	if rechecks ~= RECHECKS or gaps ~= GAPS then
		return false, `The reads gave {rechecks} rechecks a second and gaps of {gaps} ms, not {RECHECKS} and {GAPS}`
	elseif last.checks ~= 172 or last.seconds ~= 6 then
		return false, `After the reads the window kept {last.checks} and {last.seconds} as its last`
	end

	for name: string in rates do
		if name ~= "antiEspNearRechecks" and name ~= "antiEspNearGap" then
			return false, `The reads pushed {name} too`
		end
	end

	-- 2) A window's figures put each at p50 by nearest rank, and one with no samples leaves both out
	local taken: any = Window.taken()
	taken.rates.antiEspNearRechecks = { 40, 10, 30 }
	taken.rates.antiEspNearGap = { 50, 20 }
	local figures: { [string]: number } = Run.figures(taken)
	local plain: { [string]: number } = Run.figures(Window.taken())

	if figures.antiEspNearRechecks ~= 30 or figures.antiEspNearGap ~= 20 then
		return false, `The figures read {figures.antiEspNearRechecks} and {figures.antiEspNearGap}, not 30 and 20`
	elseif plain.antiEspNearRechecks ~= nil or plain.antiEspNearGap ~= nil then
		return false, "A window with no reads of the near rechecks carried their figures"
	end

	-- 3) The table: both rows straight after the hidden results, then quiet at 0 in both halves, and each kept alone
	-- where either half reads above 0
	local text: string = Compare.table("S3", HALVES, BEFORE, AFTER)
	if text ~= table.concat(TABLE, "\n") then
		return false, `The table read:\n{text}\nnot:\n{table.concat(TABLE, "\n")}`
	end

	local stillBefore: { [string]: number } = table.clone(BEFORE)
	local stillAfter: { [string]: number } = table.clone(AFTER)
	for _, still: { [string]: number } in { stillBefore, stillAfter } do
		still.antiEspNearRechecks, still.antiEspNearGap = 0, 0
	end

	local quiet: string = Compare.table("S3", HALVES, stillBefore, stillAfter)
	stillAfter.antiEspNearRechecks = 0.5
	local alone: string = Compare.table("S3", HALVES, stillBefore, stillAfter)

	if string.find(quiet, "near hidden", 1, true) or #string.split(quiet, "\n") ~= #TABLE - 2 then
		return false, `With both halves at 0, the table kept a near row:\n{quiet}`
	elseif string.find(alone, "recheck gap", 1, true) then
		return false, `With no gap in either half, the table kept its row:\n{alone}`
	elseif not string.find(alone, ALONE, 1, true) then
		return false, `With rechecks in the after half alone, the table read:\n{alone}`
	end

	-- 4) The window hands Run.near each read's seconds, never its ticks, in its one call
	local calls: { string } = {}
	for arguments: string in string.gmatch(fs.readFile(RUN), CALL) do
		table.insert(calls, arguments)
	end

	if #calls ~= 1 or string.split(calls[1], ARGUMENTS)[SECONDS_AT] ~= "stats.seconds" then
		return false, `{RUN} calls Run.near with {table.concat(calls, " and ")}, not once with stats.seconds`
	end

	return true, nil
end
