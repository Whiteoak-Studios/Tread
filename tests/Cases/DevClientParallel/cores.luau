--[[
    P6's counts measure known batches field for field as the server's
    ParallelProbe does, and print each count's line with its threads, one
    worker's wall times its workers over its own, after the serial loop
--]]

--!strict
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local FIELDS: { string } =
	{ "workers", "repeats", "batches", "wall", "wallHigh", "start", "busy", "parallelism", "byNext", "early" }

local REPEATS: number = 10
local START: number = 0.0005 -- Seconds after the send each worker starts, but the early one
local EARLY: number = -0.0001 -- The 2-worker count's last batch has its first worker start before the send
local STEP: number = 0.0001 -- Seconds each batch's wall grows by
local PASSES: number = 37
local SERIAL: { number } = { 0.002, 0.0021, 0.0019 } -- The loop's serial runs, whose p50 by nearest rank is 2 ms

-- Each count: its workers, the first batch's wall, its batches landed and the one not in by the next Heartbeat
type Count = { workers: number, wall: number, landed: number, late: number? }

local COUNTS: { Count } = {
	{ workers = 1, wall = 0.002, landed = 10, late = 1 },
	{ workers = 2, wall = 0.0025, landed = 10, late = nil },
	{ workers = 4, wall = 0.004, landed = 9, late = 1 },
}

-- Walls of 2.0 to 2.9 ms at 1 worker read p50 2.4 and p95 2.9 by nearest rank, and every worker's busy sum is its wall
-- less its start, so the p50s follow: 1.9 ms busy and 0.79 parallelism, and at 2 and 4 workers twice and four times
-- the time over walls of 2.9 and 4.4 ms, 4.8/2.9 and 15.6/4.4, threads 2 x 2.4/2.9 and 4 x 2.4/4.4
local LINE: string = table.concat({
	"P6 serial loop p50 2.000 ms at 37 passes",
	"1 worker: 10 of 10 batches, wall p50 2.400 p95 2.900 ms, start p50 0.500 ms, busy sum p50 1.900 ms, parallelism p50 0.79, threads 1.00, 9 by the next Heartbeat, 0 early",
	"2 workers: 10 of 10 batches, wall p50 2.900 p95 3.400 ms, start p50 0.500 ms, busy sum p50 4.800 ms, parallelism p50 1.66, threads 1.66, 10 by the next Heartbeat, 1 early",
	"4 workers: 9 of 10 batches, wall p50 4.400 p95 4.800 ms, start p50 0.500 ms, busy sum p50 15.600 ms, parallelism p50 3.55, threads 2.18, 8 by the next Heartbeat, 0 early",
}, "; ")

-- A count's batches, sent at 0: every worker starts at START and finishes at the batch's wall
local function batchesOf(count: Count): { any }
	local batches: { any } = {}
	for index: number = 1, count.landed do
		local wall: number = count.wall + STEP * (index - 1)
		local starts: { number } = table.create(count.workers, START)
		local finishes: { number } = table.create(count.workers, wall)

		if count.workers == 2 and index == count.landed then
			starts[1] = EARLY
		end

		table.insert(batches, { sent = 0, starts = starts, finishes = finishes, byNext = index ~= count.late })
	end

	return batches
end

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local server: any = mounted.loaded.game:GetService("ServerScriptService").Server
	local Summary: any = mounted.loaded.require(server.Parallel.Summary)

	-- 1) The copied measure gives what the server's own gives, field for field
	local measured: { any } = {}
	for _, count: Count in COUNTS do
		local ours: any = mounted.Lines.measure(count.workers, REPEATS, batchesOf(count))
		local theirs: any = Summary.measure(count.workers, REPEATS, batchesOf(count))

		for _, field: string in FIELDS do
			if ours[field] ~= theirs[field] then
				return false,
					`{count.workers} workers measured {field} {ours[field]}, where the server's gives {theirs[field]}`
			end
		end

		table.insert(measured, ours)
	end

	-- 2) The counts' line
	local line: string = mounted.Lines.counts(table.clone(SERIAL), PASSES, measured)
	if line ~= LINE then
		return false, `The counts printed "{line}", not "{LINE}"`
	end

	return true, nil
end
