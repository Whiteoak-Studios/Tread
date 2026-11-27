--[[
    A hand-built ParallelFrames arm and baseline give their lines with known
    answers by nearest rank, and every arm's line at its widest, with the
    verdict, stays whole in the report a live run keeps
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local WORKERS: number = 2
local PRE: string = "PreSimulation"
local POST: string = "PostSimulation"
local HEART: string = "Heartbeat"
local NAME: string = "ParallelFrames"
local VERDICT: string = `Runner PASS {NAME}: passed`

-- Frames ending 17, 16, 17 and 20 ms apart by os.clock(), each event's stamp beside it, the last frame never ending
local LOG: { { kind: string, at: number } } = {
	{ kind = HEART, at = 10.000 }, -- 1
	{ kind = PRE, at = 10.002 },
	{ kind = POST, at = 10.004 },
	{ kind = HEART, at = 10.017 }, -- 4
	{ kind = PRE, at = 10.019 },
	{ kind = POST, at = 10.021 },
	{ kind = HEART, at = 10.033 }, -- 7
	{ kind = PRE, at = 10.035 },
	{ kind = POST, at = 10.037 },
	{ kind = HEART, at = 10.050 }, -- 10
	{ kind = PRE, at = 10.052 },
	{ kind = POST, at = 10.054 },
	{ kind = HEART, at = 10.070 }, -- 13
	{ kind = PRE, at = 10.072 },
}

-- Four PreSimulation sends a tenth of a ms after their event's stamp: all in at the same Heartbeat, the same
-- PostSimulation with a worker that started a tenth of a ms before the send, never, and the next PreSimulation
local ROUNDS: { { [string]: any } } = {
	{ sent = 10.0021, at = 2, seen = { 1, 2 }, starts = { 10.0023, 10.0025 }, finishes = { 10.0033, 10.0040 } },
	{ sent = 10.0191, at = 5, seen = { 2 }, starts = { 10.0192, 10.0190 }, finishes = { 10.0200, 10.0202 } },
	{ sent = 10.0351, at = 8, seen = { 0, 1, 1 }, starts = {}, finishes = {} },
	{ sent = 10.0521, at = 11, seen = { 0, 1, 2 }, starts = { 10.0530, 10.0525 }, finishes = { 10.0540, 10.0600 } },
}

-- First starts 0.2, -0.1 and 0.4 ms after the send and last finishes 1.9, 1.1 and 7.9, of the three rounds all in,
-- by nearest rank of 3 the 2nd and 3rd lowest; sends 14.9, 13.9, 14.9 and 17.9 ms before their frame's Heartbeat
-- and frames of 17, 16, 17 and 20 ms, by nearest rank of 4 the 2nd and 4th lowest
local COUNTS: string =
	"all in at the same PostSimulation 1, the same Heartbeat 1, the next PreSimulation 1, the next PostSimulation 0, the next Heartbeat 0, later or never 1"
local TIMES: string =
	"send to first start p50 0.200 ms p95 0.400 ms, to last finish p50 1.900 ms p95 7.900 ms, to that frame's Heartbeat p50 14.900 ms p95 17.900 ms"
local LINE: string =
	`ParallelFrames PreSimulation send woken by a message at 1 ms: 4 rounds; {COUNTS}; {TIMES}; frame p50 17.000 ms p95 20.000 ms; 1 started before their send, 0 odd frames`

-- Two PostSimulation baseline rounds, 12.9 and 11.9 ms before their frames' Heartbeats, in frames of 17 and 16 ms
local BASELINE_ROUNDS: { { [string]: any } } = {
	{ sent = 10.0041, at = 3, seen = { 0 }, starts = {}, finishes = {} },
	{ sent = 10.0211, at = 6, seen = { 0 }, starts = {}, finishes = {} },
}

local BASELINE_LINE: string =
	"ParallelFrames PostSimulation baseline: 2 rounds, nothing handed out; send to that frame's Heartbeat p50 11.900 ms p95 12.900 ms; frame p50 16.000 ms p95 17.000 ms; 0 odd frames"

-- Frames a second past any server's rate, so an arm's odd frames stay under its whole wait times this
local FRAMES_A_SECOND: number = 1000

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Frames: any = loaded.require(server.Parallel.Frames)
	local frames: any = loaded.require(server.Config.Parallel).frames
	local live: any = loaded.require(server.Config.Live)
	local LiveRuns: any = loaded.require(loaded.game:GetService("ReplicatedStorage").Shared.Dev.LiveRuns)

	local kinds: { string } = {}
	local stamps: { number } = {}
	for _, event: { kind: string, at: number } in LOG do
		table.insert(kinds, event.kind)
		table.insert(stamps, event.at)
	end

	-- 1) The hand-built arm's line, every column and clause in its place
	local arm: any = { send = PRE, wake = "message", spin = 1 }
	local line: string = Frames.line(arm, Frames.measure(arm, kinds, stamps, ROUNDS, WORKERS))
	if line ~= LINE then
		return false, `The hand-built arm gave "{line}", not "{LINE}"`
	end

	-- 2) A baseline's line, with no workers' columns
	local baseline: any = { send = POST, wake = "none", spin = 0 }
	local baselineLine: string = Frames.line(baseline, Frames.measure(baseline, kinds, stamps, BASELINE_ROUNDS, 0))
	if baselineLine ~= BASELINE_LINE then
		return false, `The hand-built baseline gave "{baselineLine}", not "{BASELINE_LINE}"`
	end

	-- 3) Every arm's line at its widest: each column holding every round, each time a whole arm's wait, a start that
	-- wait before its send, and its frames all odd. With the verdict they all stay whole in a live run's report
	local longest: number = frames.armWait
	local report: any = LiveRuns.report(NAME, live.reportBytes, live.dropped)
	local lines: { string } = {}

	for _, each: any in Frames.arms() do
		local counts: { any } = Frames.tally({}, {}, frames.workers, each.send)
		for _, count: any in counts do
			count.count = frames.rounds
		end

		local widest: any = {
			sent = frames.rounds,
			counts = counts,
			starts = { -longest },
			finishes = { longest },
			heartbeats = { longest },
			frames = { longest },
			early = frames.rounds,
			odd = longest * FRAMES_A_SECOND,
		}

		local made: string = Frames.line(each, widest)
		table.insert(lines, made)
		LiveRuns.collect(report, made)
	end

	table.insert(lines, VERDICT)
	LiveRuns.collect(report, VERDICT)

	if report.full then
		return false, `The widest lines passed the report's {live.reportBytes} B and were cut`
	elseif not report.heard or LiveRuns.text(report) ~= table.concat(lines, "\n") then
		return false, "The widest lines were not all kept whole in the report, the verdict last"
	end

	return true, nil
end
