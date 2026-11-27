--[[
    A worker count's batches give its line with known answers by nearest
    rank, a start before the send is counted as early, a count with no batch
    in gives zeros, and one worker is named singly
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local SUMMARY: string = "dev/Server/Parallel/Summary.luau"
local SENT: number = 10 -- os.clock() at each send, so every time is taken from it
local MS: number = 0.001
local WORKERS: number = 2
local REPEATS: number = 6 -- One more than the batches, so the line shows one missing
local EMPTY_WORKERS: number = 16

-- A batch sent at SENT whose workers start and finish at those ms after it
local function batchOf(starts: { number }, finishes: { number }, byNext: boolean): { [string]: any }
	local startsAt: { number } = {}
	local finishesAt: { number } = {}
	for index: number, start: number in starts do
		table.insert(startsAt, SENT + start * MS)
		table.insert(finishesAt, SENT + finishes[index] * MS)
	end

	return { sent = SENT, starts = startsAt, finishes = finishesAt, byNext = byNext }
end

-- Two workers each busy 2 ms a batch, in no order: walls 2.25 to 5 ms, first starts 0.25 to 1 ms
local BATCHES: { { [string]: any } } = {
	batchOf({ 2, 0.5 }, { 4, 2.5 }, false), -- Wall 4 by the later worker, start 0.5 by the earlier, parallelism 1.00
	batchOf({ 0.25, 0.25 }, { 2.25, 2.25 }, true), -- Wall 2.25, start 0.25, parallelism 1.78
	batchOf({ 1, 3 }, { 3, 5 }, false), -- Wall 5, start 1, parallelism 0.80
	batchOf({ 1, 1 }, { 3, 3 }, true), -- Wall 3, start 1, parallelism 1.33
	batchOf({ 0.5, 0.5 }, { 2.5, 2.5 }, true), -- Wall 2.5, start 0.5, parallelism 1.60
}

local BY_NEXT: number = 3 -- The batches above marked in at the Heartbeat after their send

-- A worker that started half a ms before the send, and one worker's batch on its own
local EARLY: { [string]: any } = batchOf({ -0.5, 1 }, { 2, 3 }, true)
local ONE: { [string]: any } = batchOf({ 1 }, { 3 }, true)
local ONE_WORKER: number = 1
local ONE_REPEAT: number = 1

-- By nearest rank of 5: p50 the 3rd lowest and p95 the 5th
local TIMES: string = "wall p50 3.000 ms p95 5.000 ms, start p50 0.500 ms, busy sum p50 4.000 ms"
local LINE: string = `ParallelProbe 2 workers: 5 of 6 batches, {TIMES}, parallelism p50 1.33, 3 by the next Heartbeat`

local EMPTY_TIMES: string = "wall p50 0.000 ms p95 0.000 ms, start p50 0.000 ms, busy sum p50 0.000 ms"
local EMPTY_LINE: string =
	`ParallelProbe 16 workers: 0 of 6 batches, {EMPTY_TIMES}, parallelism p50 0.00, 0 by the next Heartbeat`

local ONE_TIMES: string = "wall p50 3.000 ms p95 3.000 ms, start p50 1.000 ms, busy sum p50 2.000 ms"
local ONE_LINE: string =
	`ParallelProbe 1 worker: 1 of 1 batches, {ONE_TIMES}, parallelism p50 0.67, 1 by the next Heartbeat`

return function (): (boolean, string | nil)
	local Summary: any = Harness.new().load(SUMMARY)

	-- 1) Known answers, each time from the send, the wall to the last finish and the start at the first
	local measured: any = Summary.measure(WORKERS, REPEATS, BATCHES)
	local line: string = Summary.line(measured)
	if line ~= LINE then
		return false, `The known batches gave "{line}", not "{LINE}"`
	elseif measured.batches ~= #BATCHES or measured.byNext ~= BY_NEXT or measured.early ~= 0 then
		return false,
			`The known batches counted {measured.batches} in, {measured.byNext} next and {measured.early} early`
	end

	-- 2) A worker that started before the send is counted early, which the scenario fails on
	local early: any = Summary.measure(WORKERS, REPEATS, { EARLY })
	if early.early ~= 1 then
		return false, `A batch with a start before its send counted {early.early} early, not 1`
	end

	-- 3) A count with no batch in gives zeros rather than throwing
	local empty: string = Summary.line(Summary.measure(EMPTY_WORKERS, REPEATS, {}))
	if empty ~= EMPTY_LINE then
		return false, `A count with no batch in gave "{empty}", not "{EMPTY_LINE}"`
	end

	-- 4) One worker is named singly
	local one: string = Summary.line(Summary.measure(ONE_WORKER, ONE_REPEAT, { ONE }))
	if one ~= ONE_LINE then
		return false, `One worker's batch gave "{one}", not "{ONE_LINE}"`
	end

	return true, nil
end
