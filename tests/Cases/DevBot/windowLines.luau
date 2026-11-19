--[[
    A BenchWorkers half's window prints its server, Heartbeat, tick stage,
    counts and relay clock lines in that order, each word for word as the
    window always has, and a window whose reads carried no clocks has none
--]]

--!strict
local Window = require("../../Fixtures/DevStep/Window")

local LABEL: string = "Bots S4/workers seed 1"
local BY_PLACE: string = "Tread ms a Heartbeat by its place in the tick, p50/p95, less the bots' stage"
local SUMMED: string = "decode + simulate + npcs + history + relay + finish"
local ACROSS: string = "delivery and back across a worker's clock and the main thread's"
local SEPARATOR: string = "; " -- Between the parts of one line

-- Each line's parts worked by hand from the window's figures, by nearest rank: of two values, p50 is the first and
-- p95 and p99 the second, and of four, p50 the second and p95 and p99 the fourth
local PARTS: { { string } } = {
	{
		`{LABEL} server: 64 Heartbeats a second`,
		"frame ms p50/p95/p99 17/20/20",
		"server FPS p10 50",
		"Stats.HeartbeatTime p50/p95/p99 0.005/0.007/0.007",
		"Stats.PhysicsStepTime p50/p95/p99 0.002/0.004/0.004",
		"Stats.DataSendKbps p50/p95/p99 3.5/3.75/3.75",
	},
	{
		`{LABEL} {BY_PLACE}: the tick's Heartbeat 3.000/5.000 with the bots' stage 1.000/1.000 over 2`,
		"the one after 2.000/3.000 with the bots' stage 0.000/0.000 over 2",
		"the one after that 0.500/1.000 with the bots' stage 0.000/0.000 over 2",
		"later 0.250/0.250 with the bots' stage 0.000/0.000 over 2",
		"2 rounds in by the next Heartbeat, 0 later",
		"1 Heartbeats not read",
	},
	{
		`{LABEL} Tread tick stages a tick, {SUMMED}, ms p50/p95/p99 4.000/6.000/6.000`,
		"2 ticks",
		"antiEsp p95 ms beside them, p50/p95/p99 over the reads 0.625/0.875/0.875",
		"the finish alone ms p50/p95/p99 1.500/2.500/2.500 over 2 held ticks",
		"0 rounds dropped",
	},
	{
		`{LABEL} counts, p50/p95/p99 over the reads: recordsSent a relay run 100.000/140.000/140.000`,
		"recordsCut a relay run 0.000/2.000/2.000",
		"bytesOut a relay run 2000.000/2400.000/2400.000",
		"antiEspTests a tick 50.000/70.000/70.000",
	},
	{
		`{LABEL} relay clocks, ms p50/p95/p99 over the reads, {ACROSS}: head 0.250/0.500/0.500`,
		"back 1.000/2.000/2.000",
	},
}

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local expected: { string } = {}
	for _, parts: { string } in PARTS do
		table.insert(expected, table.concat(parts, SEPARATOR))
	end

	-- 1) Every line in order, word for word
	local lines: { string } = Run.lines(LABEL, Window.taken())
	if #lines ~= #expected then
		return false, `The window printed {#lines} lines, not {#expected}`
	end

	for index: number, line: string in expected do
		if lines[index] ~= line then
			return false, `The window's line {index} read:\n{lines[index]}\nnot:\n{line}`
		end
	end

	-- 2) Reads with no clocks: the first four lines alone
	local plain: any = Window.taken()
	plain.samples["clock headMs"] = nil
	plain.samples["clock backMs"] = nil

	local unclocked: { string } = Run.lines(LABEL, plain)
	if #unclocked ~= #expected - 1 or unclocked[#unclocked] ~= expected[#expected - 1] then
		return false, `A window with no clocks printed {#unclocked} lines, ending:\n{unclocked[#unclocked]}`
	end

	return true, nil
end
