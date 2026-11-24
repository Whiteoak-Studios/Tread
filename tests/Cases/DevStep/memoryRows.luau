--[[
    Verdict memory's two rows: each read's change over its ticks, at p50
    in a window's figures, two quiet rows after the rays', and a memory run
    failing on nothing shown or memory shown off, a refused half unjudged
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Step = require("../../Fixtures/DevStep/Step")
local Window = require("../../Fixtures/DevStep/Window")

local HALVES: { string } = { "before", "after" }
local NOTHING: string = "Bots Rooms150/after: verdict memory showed no test answered from memory and no ray a kept box blocked, so the run "
	.. "showed nothing"
local OFF_SHOWED: string = "Bots Rooms150/before: with verdict memory off, it showed 2.5 tests answered from memory and "
	.. "0.0 rays a kept box blocked a tick at p50"

-- Each read of the running totals and its ticks, from totals of 100 and 1,000 as the window opened: 40 tests and 800
-- rays over 20 ticks, a read whose ticks all dropped, then 5 and 50 over 10 ticks from that read's totals, and a read
-- with no tick count
type Read = { kept: number, boxRays: number, ticks: any }

local READS: { Read } = {
	{ kept = 140, boxRays = 1800, ticks = 20 },
	{ kept = 145, boxRays = 1850, ticks = 0 },
	{ kept = 150, boxRays = 1900, ticks = 10 },
	{ kept = 160, boxRays = 2000, ticks = nil },
}

-- The halves' figures for the rows, with the rays' and hidden results' rows beside them
local BEFORE: { [string]: number } = { antiEspRays = 1500, antiEspKept = 0, antiEspBoxRays = 0, antiEspHidden = 10 }
local AFTER: { [string]: number } = { antiEspRays = 1200, antiEspKept = 12.5, antiEspBoxRays = 600, antiEspHidden = 5 }

-- Worked by hand: each change after less before at one decimal place, with no percent over a before of 0
local TABLE: { string } = {
	"Rooms150 table, figure: before after change percent",
	"antiEsp rays a tick p50: 1500.0 1200.0 -300.0 -20.0%",
	"antiEsp tests answered from memory a tick p50: 0.0 12.5 +12.5 n/a",
	"antiEsp rays a kept box blocked a tick p50: 0.0 600.0 +600.0 n/a",
	"antiEsp hidden results: 10 5 -5 -50.0%",
}

-- A memory run's stand-in halves, each showing the figures given for it, or failing for false
local function answers(before: { [string]: number } | false, after: { [string]: number } | false): Step.Answer
	return function (_: string, half: string?): (boolean, string, { [string]: number }?)
		local figures: { [string]: number } | false = after
		if half == "before" then
			figures = before
		end

		if figures == false then
			return false, `Bots Rooms150/{half} seed 1: a stand-in failure`, nil
		end

		return true, `Bots Rooms150/{half} seed 1: drove and cleaned up`, figures
	end
end

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) Each read's changes over its ticks, a read with no ticks pushing nothing but still kept as the last
	local last: any = { kept = 100, boxRays = 1000 }
	local rates: { [string]: { number } } = {}
	for _, read: Read in READS do
		Run.memory(last, read.kept, read.boxRays, read.ticks, rates)
	end

	local kept: string = table.concat(rates.antiEspKept or {}, ",")
	local boxRays: string = table.concat(rates.antiEspBoxRays or {}, ",")
	if kept ~= "2,0.5" or boxRays ~= "40,5" then
		return false, `The reads gave {kept} tests from memory and {boxRays} box rays a tick, not 2,0.5 and 40,5`
	elseif last.kept ~= 160 or last.boxRays ~= 2000 then
		return false, `After the reads the window kept {last.kept} and {last.boxRays} as its last`
	end

	for name: string in rates do
		if name ~= "antiEspKept" and name ~= "antiEspBoxRays" then
			return false, `The reads pushed {name} too`
		end
	end

	-- 2) A window's figures put each at p50 by nearest rank, and one with no samples leaves both out
	local taken: any = Window.taken()
	taken.rates.antiEspKept = { 3, 1, 2 }
	taken.rates.antiEspBoxRays = { 40, 10 }
	local figures: { [string]: number } = Run.figures(taken)
	local plain: { [string]: number } = Run.figures(Window.taken())

	if figures.antiEspKept ~= 2 or figures.antiEspBoxRays ~= 10 then
		return false, `The window's figures were {figures.antiEspKept} and {figures.antiEspBoxRays}, not 2 and 10`
	elseif plain.antiEspKept ~= nil or plain.antiEspBoxRays ~= nil then
		return false, "A window with no reads of verdict memory carried its figures"
	end

	-- 3) The table: both rows straight after the rays', one place each, then quiet at 0 in both halves, and each kept
	-- alone where either half reads above 0
	local text: string = Compare.table("Rooms150", HALVES, BEFORE, AFTER)
	if text ~= table.concat(TABLE, "\n") then
		return false, `The table read:\n{text}\nnot:\n{table.concat(TABLE, "\n")}`
	end

	local still: { [string]: number } = table.clone(AFTER)
	still.antiEspKept, still.antiEspBoxRays = 0, 0
	local quiet: string = Compare.table("Rooms150", HALVES, BEFORE, still)
	local boxed: { [string]: number } = table.clone(still)
	boxed.antiEspBoxRays = 0.5
	local alone: string = Compare.table("Rooms150", HALVES, BEFORE, boxed)

	if string.find(quiet, "from memory", 1, true) or string.find(quiet, "kept box", 1, true) then
		return false, `With both halves at 0, the table kept a memory row:\n{quiet}`
	elseif string.find(alone, "from memory", 1, true) then
		return false, `With no test from memory in either half, the table kept its row:\n{alone}`
	elseif not string.find(alone, "\nantiEsp rays a kept box blocked a tick p50: 0.0 0.5 +0.5 n/a\n", 1, true) then
		return false, `With box rays in the after half alone, the table read:\n{alone}`
	end

	-- 4) A memory run whose after half showed neither count fails, saying it showed nothing
	local empty: Step.Mounted = Step.load(answers(BEFORE, still))
	local passed: boolean, reason: string? = empty.BenchStep("memory")
	if passed then
		return false, "A memory run whose after half showed nothing passed"
	elseif not string.find(reason or "", NOTHING, 1, true) then
		return false, `A memory run whose after half showed nothing gave:\n{reason}`
	end

	-- 5) And one whose before half, with memory off, showed a test answered from memory fails, naming what it showed
	local leaky: { [string]: number } = table.clone(BEFORE)
	leaky.antiEspKept = 2.5
	local leaked: Step.Mounted = Step.load(answers(leaky, AFTER))
	passed, reason = leaked.BenchStep("memory")
	if passed then
		return false, "A memory run whose before half showed memory passed"
	elseif not string.find(reason or "", OFF_SHOWED, 1, true) then
		return false, `A memory run whose before half showed memory gave:\n{reason}`
	elseif string.find(reason or "", "showed nothing", 1, true) then
		return false, `A memory run whose after half showed memory said it showed nothing:\n{reason}`
	end

	-- 6) Box rays alone in the after half are enough, and a half that failed gives no figures to judge
	passed, reason = Step.load(answers(BEFORE, boxed)).BenchStep("memory")
	if not passed then
		return false, `A memory run whose after half showed box rays alone failed: {reason}`
	end

	passed, reason = Step.load(answers(BEFORE, false)).BenchStep("memory")
	if passed then
		return false, "A memory run whose after half failed passed"
	elseif string.find(reason or "", "showed nothing", 1, true) then
		return false, `A memory run whose after half failed was judged on figures it never gave:\n{reason}`
	end

	-- 7) A half whose verdict memory flip was refused fails naming the refusal alone, never judged on its figures as if
	-- memory had been set: the after half's refused on with nothing shown, then the before half's refused off with
	-- memory shown
	for _, case: { refusing: boolean, before: { [string]: number }, after: { [string]: number }, judged: string } in
		{
			{ refusing = true, before = BEFORE, after = still, judged = "showed nothing" },
			{ refusing = false, before = leaky, after = AFTER, judged = "with verdict memory off" },
		}
	do
		local refused: Step.Mounted = Step.load(answers(case.before, case.after))
		for _, lever: any in refused.Levers.list do
			if lever.name == "verdictMemory" then
				local useMemory: (on: boolean) -> () = lever.set
				lever.set = function (on: boolean)
					if on == case.refusing then
						error("a stand-in refusal", 0)
					end

					useMemory(on)
				end
			end
		end

		local half: string = case.refusing and "after" or "before"
		passed, reason = refused.BenchStep("memory")
		if passed then
			return false, `A memory run whose {half} half's flip was refused passed`
		elseif
			not string.find(reason or "", `Bots Rooms150/{half}'s levers refused: verdictMemory refused `, 1, true)
		then
			return false, `A memory run whose {half} half's flip was refused named no refusal:\n{reason}`
		elseif string.find(reason or "", case.judged, 1, true) then
			return false, `A memory run whose {half} half's flip was refused was judged on its figures:\n{reason}`
		end
	end

	return true, nil
end
