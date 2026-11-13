--[[
    The probe's closing line with known answers: the serial loop's p50 from
    a list it leaves in order, the first count of the highest parallelism,
    and only the counts whose every batch asked for was in by the next Heartbeat
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local SUMMARY: string = "dev/Server/Parallel/Summary.luau"
local MS: number = 0.001
local PASSES: number = 87
local REPEATS: number = 6
local SERIAL: { number } = { 3 * MS, 1 * MS, 2 * MS } -- p50 by nearest rank of 3 is the 2nd lowest, 2 ms

-- A count as the probe measures one, with only what the closing line reads set apart from zeros
local function countOf(workers: number, batches: number, parallelism: number, byNext: number): { [string]: any }
	return {
		workers = workers,
		repeats = REPEATS,
		batches = batches,
		wall = 0,
		wallHigh = 0,
		start = 0,
		busy = 0,
		parallelism = parallelism,
		byNext = byNext,
		early = 0,
	}
end

local BASELINE: string = "ParallelProbe summary: serial loop p50 2.000 ms at 87 passes"
local IN_TIME: string = "worker counts with every batch in by the next Heartbeat:"

return function (): (boolean, string | nil)
	local Summary: any = Harness.new().load(SUMMARY)

	-- 1) 4 workers peak before 8's tie, and 8 is left out of the list for stopping short though its batches came next
	local counts: { { [string]: any } } = {
		countOf(1, REPEATS, 0.98, REPEATS),
		countOf(2, REPEATS, 1.9, REPEATS - 1),
		countOf(4, REPEATS, 3.25, REPEATS),
		countOf(8, REPEATS / 2, 3.25, REPEATS / 2),
		countOf(16, 0, 0, 0),
	}

	local expected: string = `{BASELINE}; parallelism peaked at p50 3.25 with 4 workers; {IN_TIME} 1, 4`
	local closed: string = Summary.close(SERIAL, PASSES, counts)
	if closed ~= expected then
		return false, `The known counts closed with "{closed}", not "{expected}"`
	elseif SERIAL[1] ~= 3 * MS or SERIAL[2] ~= 1 * MS then
		return false, "The closing line sorted the serial times it was handed"
	end

	-- 2) No batch in anywhere names no peak and no count
	local none: string = `{BASELINE}; no batch landed at any count; {IN_TIME} none`
	local empty: string = Summary.close(SERIAL, PASSES, { countOf(1, 0, 0, 0), countOf(2, 0, 0, 0) })
	if empty ~= none then
		return false, `Counts with no batch in closed with "{empty}", not "{none}"`
	end

	-- 3) A peak at one worker is named singly
	local single: string = `{BASELINE}; parallelism peaked at p50 0.97 with 1 worker; {IN_TIME} 1`
	local one: string = Summary.close(SERIAL, PASSES, { countOf(1, REPEATS, 0.97, REPEATS) })
	if one ~= single then
		return false, `One worker's count closed with "{one}", not "{single}"`
	end

	return true, nil
end
