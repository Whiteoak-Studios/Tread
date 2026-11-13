--[[
    ParallelProbe's arithmetic: one worker count's batches measured by
    nearest rank into its line, and the closing line over every count, with
    the rank and the worker count's noun ParallelReturn's lines use too
--]]

--!strict
local PREFIX: string = "ParallelProbe" -- What each of the probe's lines begins with
local MILLISECONDS: number = 1000
local P50: number = 0.5
local P95: number = 0.95
local NONE: string = "none" -- The closing line's list when no count had every batch in by the next Heartbeat
local LIST_SEPARATOR: string = ", "
local CLAUSE_SEPARATOR: string = "; "

-- One batch as it landed: when it was sent and each worker's start and finish, all by os.clock()
export type Batch = {
	sent: number,
	starts: { number },
	finishes: { number },
	byNext: boolean, -- Whether every worker's marks were in at the Heartbeat after the send
}

-- One worker count's batches by nearest rank, every time in seconds
export type Measured = {
	workers: number,
	repeats: number, -- Batches asked for
	batches: number, -- Batches that landed
	wall: number, -- p50 from the send to the last worker's finish
	wallHigh: number, -- p95 of the same
	start: number, -- p50 from the send to the first worker's start
	busy: number, -- p50 of the workers' own times, summed over each batch
	parallelism: number, -- p50 of each batch's summed time over its wall time
	byNext: number, -- Batches with every worker's marks in at the Heartbeat after the send
	early: number, -- Batches a worker started before the send, which only a clock other than the main thread's gives
}

local Summary = {}

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
function Summary.rank(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

-- A worker count with its noun, "1 worker" or "8 workers"
function Summary.named(workers: number): string
	local noun: string = workers == 1 and "worker" or "workers"

	return `{workers} {noun}`
end

--[[
    One worker count's batches by nearest rank: each batch's wall time from
    its send to its last finish, its first start, the workers' summed time
    and that sum over the wall time, with the batches in by the next
    Heartbeat and those a worker started before the send counted
--]]

function Summary.measure(workers: number, repeats: number, batches: { Batch }): Measured
	local walls: { number } = {}
	local starts: { number } = {}
	local busy: { number } = {}
	local parallel: { number } = {}
	local byNext: number = 0
	local early: number = 0

	for _, batch: Batch in batches do
		local first: number = math.huge
		local last: number = -math.huge
		local summed: number = 0

		for worker: number, start: number in batch.starts do
			local finish: number = batch.finishes[worker]
			first = math.min(first, start)
			last = math.max(last, finish)
			summed += finish - start
		end

		local wall: number = last - batch.sent
		table.insert(walls, wall)
		table.insert(starts, first - batch.sent)
		table.insert(busy, summed)
		table.insert(parallel, wall > 0 and summed / wall or 0)

		if batch.byNext then
			byNext += 1
		end

		if first < batch.sent then
			early += 1
		end
	end

	return {
		workers = workers,
		repeats = repeats,
		batches = #batches,
		wall = Summary.rank(walls, P50),
		wallHigh = Summary.rank(walls, P95),
		start = Summary.rank(starts, P50),
		busy = Summary.rank(busy, P50),
		parallelism = Summary.rank(parallel, P50),
		byNext = byNext,
		early = early,
	}
end

-- One worker count's line, its times in ms
function Summary.line(measured: Measured): string
	local head: string = `{PREFIX} {Summary.named(measured.workers)}: {measured.batches} of {measured.repeats} batches`
	local times: string = string.format(
		"wall p50 %.3f ms p95 %.3f ms, start p50 %.3f ms, busy sum p50 %.3f ms",
		measured.wall * MILLISECONDS,
		measured.wallHigh * MILLISECONDS,
		measured.start * MILLISECONDS,
		measured.busy * MILLISECONDS
	)

	local parallelism: string = string.format("parallelism p50 %.2f", measured.parallelism)

	return `{head}, {times}, {parallelism}, {measured.byNext} by the next Heartbeat`
end

--[[
    The closing line: the loop's serial p50 and its passes, the count whose
    parallelism p50 is highest among those with a batch in, the first of
    any tie, and each count whose every batch asked for was in by the next
    Heartbeat
--]]

function Summary.close(serial: { number }, passes: number, counts: { Measured }): string
	local serialMs: string = string.format("%.3f", Summary.rank(table.clone(serial), P50) * MILLISECONDS)
	local baseline: string = `serial loop p50 {serialMs} ms at {passes} passes`

	local peak: Measured? = nil
	local onTime: { string } = {}

	for _, measured: Measured in counts do
		local highest: Measured? = peak
		if measured.batches > 0 and (not highest or measured.parallelism > highest.parallelism) then
			peak = measured
		end

		if measured.batches > 0 and measured.batches == measured.repeats and measured.byNext == measured.batches then
			table.insert(onTime, `{measured.workers}`)
		end
	end

	local peaked: string = "no batch landed at any count"
	if peak then
		peaked = string.format("parallelism peaked at p50 %.2f with %s", peak.parallelism, Summary.named(peak.workers))
	end

	local listed: string = NONE
	if #onTime > 0 then
		listed = table.concat(onTime, LIST_SEPARATOR)
	end

	local inTime: string = `worker counts with every batch in by the next Heartbeat: {listed}`

	return `{PREFIX} summary: {table.concat({ baseline, peaked, inTime }, CLAUSE_SEPARATOR)}`
end

return Summary
