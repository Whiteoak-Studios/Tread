--[[
    A run's report hears the Runner's verdict line for that run alone,
    passed or failed, even once the line is cut, and a report that never
    heard it ends with a line saying it didn't arrive in the wait's time
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local CONFIG: string = "dev/Server/Config/Live.luau"
local RUN: string = "BenchS1"
local SMALL: number = 64 -- Bytes of a head small enough for a few lines to pass it

-- Lines that are no verdict line for the run, each beside why
local NOT_VERDICTS: { string } = {
	"Runner PASS BenchS10: passed", -- Another run whose name starts with this one's
	"Runner PASS BotsSmoke: passed", -- Another run
	"Warning: Runner PASS BenchS1: passed", -- The verdict's words, not at the line's start
	"Runner passed BenchS1", -- Not the Runner's format
}

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local LiveRuns: any = place.load(LIVE_RUNS)
	local config: any = place.load(CONFIG)
	local seconds: number = config.verdictWait

	if not (seconds > 0) then
		return false, `The verdict line's wait is {seconds} s`
	end

	-- 1) Only the Runner's own verdict line for the run counts, passed or failed
	local report: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	for _, line: string in NOT_VERDICTS do
		LiveRuns.collect(report, line)
		if report.heard then
			return false, `The report for {RUN} heard its verdict in {line}`
		end
	end

	local failed: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	LiveRuns.collect(failed, `Runner FAIL {RUN}: it threw: nothing to run`)
	LiveRuns.collect(report, `Runner PASS {RUN}: passed`)
	if not report.heard or not failed.heard then
		return false, `The report missed its verdict line, passed ({report.heard}) or failed ({failed.heard})`
	end

	-- 2) The line counts once it arrives, even when the head is full and later lines cut it
	local full: any = LiveRuns.report(RUN, SMALL, config.dropped)
	LiveRuns.collect(full, string.rep("x", SMALL))
	LiveRuns.collect(full, `Runner PASS {RUN}: passed`)
	LiveRuns.collect(full, "A line printed after the verdict")
	if not full.heard then
		return false, "A verdict line past the head and then cut went unheard"
	end

	-- 3) A report that heard its verdict closes as it was
	local before: string = LiveRuns.text(report)
	LiveRuns.close(report, seconds)
	if LiveRuns.text(report) ~= before then
		return false, `Closing a report that heard its verdict changed it to:\n{LiveRuns.text(report)}`
	end

	-- 4) One that never heard it ends with a line saying so, naming the run and the wait
	local silent: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	LiveRuns.collect(silent, "Bots S7 seed 1: starting")
	LiveRuns.close(silent, seconds)

	local lines: { string } = string.split(LiveRuns.text(silent), "\n")
	local note: string = `No verdict line from the Runner for {RUN} arrived within {seconds} s`
	if #lines ~= 2 or lines[2] ~= note then
		return false, `A report that never heard its verdict ended with {lines[#lines]}, not {note}`
	end

	return true, nil
end
