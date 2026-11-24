--[[
    The crowd cap's row is the viewer-player pairs past the cap a relay
    run: each read's count over its relay runs, at p50 in a window's
    figures, a quiet row after the records cut, at one decimal place
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Window = require("../../Fixtures/DevStep/Window")

local HALVES: { string } = { "before", "after" }

-- Each read's ticks, relay ticks skipped and candidates past a cap's size, summed over every viewer's turn
local READS: { { [string]: number } } = {
	{ ticks = 20, relaySkipped = 2, crowdRest = 27 }, -- 27 over 18 relay runs
	{ ticks = 3, relaySkipped = 3, crowdRest = 5 }, -- Every relay tick skipped: no relay run
	{ ticks = 0, relaySkipped = 0, crowdRest = 4 }, -- Every tick dropped
	{ ticks = 20, relaySkipped = 0, crowdRest = 45 }, -- 45 over 20
	{ ticks = 10, relaySkipped = 0 }, -- A read with no count
}

-- The rows around it, worked by hand at one decimal place, with no percent over a before of 0
local TABLE: { string } = {
	"S4 table, figure: before after change percent",
	"records cut a relay run p50: 0.0 12.5 +12.5 n/a",
	"viewer-player pairs past the crowd cap a relay run p50: 0.0 117.5 +117.5 n/a",
	"bytes a relay run p50: 20000.0 19000.0 -1000.0 -5.0%",
}

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) Each read's count over its relay runs, none where it ran none, and nothing else pushed
	local rates: { [string]: { number } } = {}
	for _, read: { [string]: number } in READS do
		Run.counts(read, rates)
	end

	if table.concat(rates.crowdRest or {}, ",") ~= "1.5,2.25" then
		return false, `The reads gave {table.concat(rates.crowdRest or {}, ",")} pairs past a relay run, not 1.5,2.25`
	end

	for name: string in rates do
		if name ~= "crowdRest" then
			return false, `The reads pushed {name} too`
		end
	end

	-- 2) A window's figure is that rate's p50 by nearest rank, never the reads' counts summed
	local taken: any = Window.taken()
	taken.rates.crowdRest = { 2.25, 117.5, 1.5 }
	taken.samples.crowdRest = { 999, 999, 999 }
	local figure: number? = Run.figures(taken).crowdRest
	if figure ~= 2.25 then
		return false, `The window's crowd figure was {figure}, not the rate's p50 of 2.25`
	end

	-- 3) The row after the records cut at one place, and quiet: gone when both halves read 0
	local text: string = Compare.table("S4", HALVES, { recordsCut = 0, crowdRest = 0, bytes = 20000 }, {
		recordsCut = 12.5,
		crowdRest = 117.5,
		bytes = 19000,
	})

	if text ~= table.concat(TABLE, "\n") then
		return false, `The table read:\n{text}\nnot:\n{table.concat(TABLE, "\n")}`
	end

	local quiet: string = Compare.table("S4", HALVES, { crowdRest = 0, bytes = 1 }, { crowdRest = 0, bytes = 1 })
	if string.find(quiet, "crowd cap", 1, true) then
		return false, `With both halves at 0, the table kept the crowd cap's row:\n{quiet}`
	end

	return true, nil
end
