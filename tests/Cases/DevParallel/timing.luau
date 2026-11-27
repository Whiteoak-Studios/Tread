--[[
    P1's lines with known answers: a round is in before the next
    PreSimulation only when every event came in its frame, a missing event
    is counted, and the arm's callbacks outside the rounds' frames left out
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local WORKERS: number = 2

-- Three rounds a frame apart: all in that frame, one event a frame late, and one event never back
local ROUNDS: { { [string]: any } } = {
	{
		frame = 5,
		sent = 10,
		starts = { 10.0005, 10.001 },
		finishes = { 10.0015, 10.002 },
		arrivals = { 5, 5 },
		landed = { 10.002, 10.003 },
		polled = true,
	},
	{
		frame = 6,
		sent = 11,
		starts = { 11.002, 11.0025 },
		finishes = { 11.003, 11.0035 },
		arrivals = { 6, 7 },
		landed = { 11.004, 11.02 },
		polled = false,
	},
	{
		frame = 7,
		sent = 12,
		starts = { 12.003 },
		finishes = { 12.004 },
		arrivals = { 7 },
		landed = { 12.005 },
		polled = false,
	},
}

-- Each round's frame's main Heartbeat start, 5 ms before the round's send
local HEARTBEATS: { [number]: number } = { [5] = 9.995, [6] = 10.995, [7] = 11.995 }

-- The arm's callbacks: one a frame before the rounds and one after, both left out, and three inside them
local BEATS: { { [string]: number } } = {
	{ parallel = 9.006, frame = 4, synchronized = 4, arrived = 4 },
	{ parallel = 10.006, frame = 5, synchronized = 5, arrived = 5 },
	{ parallel = 11.007, frame = 6, synchronized = 6, arrived = 7 },
	{ parallel = 12.008, frame = 7, synchronized = 8, arrived = 8 },
	{ parallel = 13.009, frame = 8, synchronized = 8, arrived = 8 },
}

-- The lines those give, each long one built from its clauses
local EVENTS: string = "P1 events: 1 of 3 rounds (33.3%) had all 2 in before the next PreSimulation"
local LAST: string = "the last one's arrival minus send p50 3.000 ms p95 20.000 ms, over 3 PreSimulations"
local WORK: string = "start minus send p50 2.000 ms p95 3.000 ms, finish minus send p50 3.000 ms p95 4.000 ms"
local ARM: string = "P1 ConnectParallel arm: 3 callbacks over 3 frames"
local OFFSET: string = "parallel start minus that frame's main Heartbeat p50 12.000 ms p95 13.000 ms over 3"
local SAME: string = "synchronized in that frame 2 (66.7%), on the main thread in that frame 1 (33.3%)"

local EXPECTED: { string } = {
	`{EVENTS} and 2 had all 2 in at all, {LAST}`,
	"P1 deferred poll: 1 of 3 rounds (33.3%) found every worker's round in the frame it was sent",
	`P1 workers: {WORK}, over 5 events`,
	`{ARM}, {OFFSET}, {SAME}`,
}

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Timings: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Timings)

	-- 1) The one event never back is the one missing
	local missing: number = Timings.missing(ROUNDS, WORKERS)
	if missing ~= 1 then
		return false, `The rounds were missing {missing} events, not 1`
	end

	-- 2) The known rounds and callbacks give the known lines
	local lines: { string } = Timings.timing(WORKERS, ROUNDS, HEARTBEATS, BEATS)
	if #lines ~= #EXPECTED then
		return false, `P1 gave {#lines} lines, not {#EXPECTED}`
	end

	for index: number, expected: string in EXPECTED do
		if lines[index] ~= expected then
			return false, `P1's line {index} was "{lines[index]}", not "{expected}"`
		end
	end

	return true, nil
end
