--[[
    The client probes' arithmetic and lines: P6's batches measured as the
    server's probe measures them, its counts and landings, P8's arms step by
    step with the foot's lag, and the line the dev scope's clientCost carries
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Frames = require(ReplicatedStorage.Shared.Dev.Frames)
local Work = require(script.Parent.Work)

local P50: number = 0.5
local P95: number = 0.95
local MILLISECONDS: number = 1000
local PERCENT: number = 100
local LINE_BYTES: number = 2048 -- The most clientCost's line carries, string(1..2048) in dev/Schemas/Dev.volt
local SHARE: string = "%.1f%%" -- A share of a count, as a line prints it
local SEPARATOR: string = "; " -- Between a line's clauses
local LIST: string = ", " -- Between the figures of a list inside a clause

type Rise = Work.Rise

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

-- One of P8's arms step by step, every time in seconds
export type Arm = {
	workers: number, -- 0 for the main thread's own serial arm
	spans: { number }, -- Each step the main thread stamped, from its PreSimulation to its PostSimulation
	computes: { number }, -- Each step every callback reached, its solves summed over its callbacks
	writes: { number }, -- And its writes summed
	walls: { number }, -- And from its first callback's start to its last one's last write
	callbacks: number, -- Over the stamped steps
	inStep: number, -- Of those, the ones whose writes were done before their step's PostSimulation
	early: number, -- Of those, the ones that started before the main thread's PreSimulation stamp
	lags: { number }, -- Each foot read's lag, in steps
}

-- One stamped step's callbacks, gathered across the workers
type Step = {
	callbacks: number,
	compute: number,
	write: number,
	first: number,
	last: number,
}

local Lines = {}

-- A worker count with its noun, "1 worker" or "8 workers"
function Lines.named(workers: number): string
	local noun: string = workers == 1 and "worker" or "workers"

	return `{workers} {noun}`
end

-- A count as a share of the total, 0 for a total of none
local function share(count: number, total: number): string
	local percent: number = 0
	if total > 0 then
		percent = PERCENT * count / total
	end

	return string.format(SHARE, percent)
end

--[[
    One worker count's batches by nearest rank: each batch's wall time from
    its send to its last finish, its first start, the workers' summed time
    and that sum over the wall time, with the batches in by the next
    Heartbeat and those a worker started before the send counted
--]]

function Lines.measure(workers: number, repeats: number, batches: { Batch }): Measured
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
		wall = Frames.percentile(walls, P50),
		wallHigh = Frames.percentile(walls, P95),
		start = Frames.percentile(starts, P50),
		busy = Frames.percentile(busy, P50),
		parallelism = Frames.percentile(parallel, P50),
		byNext = byNext,
		early = early,
	}
end

--[[
    P6's counts: the loop's serial p50 and its passes, then each count's
    batches with its threads, its workers times one worker's wall over its
    own wall, which is 0 with no one-worker count or a count with no wall
--]]

function Lines.counts(serial: { number }, passes: number, counts: { Measured }): string
	local loop: number = Frames.percentile(table.clone(serial), P50) * MILLISECONDS
	local clauses: { string } = { string.format("P6 serial loop p50 %.3f ms at %d passes", loop, passes) }

	local one: number = 0
	for _, measured: Measured in counts do
		if measured.workers == 1 then
			one = measured.wall
		end
	end

	for _, measured: Measured in counts do
		local threads: number = 0
		if measured.wall > 0 then
			threads = measured.workers * one / measured.wall
		end

		local head: string = `{Lines.named(measured.workers)}: {measured.batches} of {measured.repeats} batches`
		local times: string = string.format(
			"wall p50 %.3f p95 %.3f ms, start p50 %.3f ms, busy sum p50 %.3f ms",
			measured.wall * MILLISECONDS,
			measured.wallHigh * MILLISECONDS,
			measured.start * MILLISECONDS,
			measured.busy * MILLISECONDS
		)

		local ran: string = string.format("parallelism p50 %.2f, threads %.2f", measured.parallelism, threads)
		local landed: string = `{measured.byNext} by the next Heartbeat, {measured.early} early`
		table.insert(clauses, `{head}, {times}, {ran}, {landed}`)
	end

	return table.concat(clauses, SEPARATOR)
end

--[[
    One landing arm's clause from its workers' samples: the callbacks over
    the events counted, the wait from each callback's synchronize to its
    resume, and for each frame event the share of callbacks that resumed
    before the next one fired, as their two reads of its count give it
--]]

function Lines.landing(event: string, samples: { { number } }, events: number): string
	local layout = Work.LANDING
	local names: { string } = Work.EVENTS
	local callbacks: number = 0
	local waits: { number } = {}
	local before: { number } = table.create(#names, 0)

	for _, list: { number } in samples do
		for at: number = 0, #list - layout.STRIDE, layout.STRIDE do
			callbacks += 1
			table.insert(waits, list[at + layout.SYNCED] - list[at + layout.SPUN])

			for index: number = 1, #names do
				-- How many of that event fired between the callback's read before it synchronized and its read after
				local fired: number = list[at + layout.AFTER + index - 1] - list[at + layout.BEFORE + index - 1]
				if fired < 1 then
					before[index] += 1
				end
			end
		end
	end

	local shares: { string } = {}
	for index: number, name: string in names do
		table.insert(shares, `{name} {share(before[index], callbacks)}`)
	end

	local wait: string = string.format(
		"synchronize wait p50 %.3f p95 %.3f ms",
		Frames.percentile(waits, P50) * MILLISECONDS,
		Frames.percentile(waits, P95) * MILLISECONDS
	)

	local resumed: string = `synchronized before the next {table.concat(shares, LIST)}`

	return `{event} arm: {callbacks} callbacks over {events} events, {wait}, {resumed}`
end

--[[
    One of P8's arms step by step from the main thread's stamps and each
    worker's samples, the serial arm handing in the main thread's own as a
    single worker's: each stamped step's span, and each step every worker
    reached, its solves and writes summed over them and its wall, with the
    writes done in their step and the starts early counted
--]]

function Lines.arm(
	workers: number,
	pres: { [number]: number },
	posts: { [number]: number },
	samples: { { number } },
	lags: { number }
): Arm
	local layout = Work.BENDING
	local spans: { number } = {}

	for step: number, pre: number in pres do
		local post: number? = posts[step]
		if post then
			table.insert(spans, post - pre)
		end
	end

	local steps: { [number]: Step } = {}
	local callbacks: number = 0
	local inStep: number = 0
	local early: number = 0

	for _, list: { number } in samples do
		for at: number = 0, #list - layout.STRIDE, layout.STRIDE do
			local step: number = list[at + layout.STEP]
			local pre: number? = pres[step]

			if pre and posts[step] then
				local start: number = list[at + layout.START]
				local written: number = list[at + layout.WRITTEN]
				callbacks += 1

				-- No PostSimulation fired between the read before it synchronized and the one after
				if list[at + layout.AFTER] - list[at + layout.BEFORE] < 1 then
					inStep += 1
				end

				if start < pre then
					early += 1
				end

				local gathered: Step = steps[step]
					or { callbacks = 0, compute = 0, write = 0, first = math.huge, last = -math.huge }

				steps[step] = gathered
				gathered.callbacks += 1
				gathered.compute += list[at + layout.SOLVED] - start
				gathered.write += written - list[at + layout.SYNCED]
				gathered.first = math.min(gathered.first, start)
				gathered.last = math.max(gathered.last, written)
			end
		end
	end

	local computes: { number } = {}
	local writes: { number } = {}
	local walls: { number } = {}

	-- A step only some workers reached is left out, so every sum covers each of them
	for _, gathered: Step in steps do
		if gathered.callbacks == #samples then
			table.insert(computes, gathered.compute)
			table.insert(writes, gathered.write)
			table.insert(walls, gathered.last - gathered.first)
		end
	end

	return {
		workers = workers,
		spans = spans,
		computes = computes,
		writes = writes,
		walls = walls,
		callbacks = callbacks,
		inStep = inStep,
		early = early,
		lags = lags,
	}
end

-- The foot reads' lags, at 0 steps, at 1 and at more, as a clause prints them
local function footOf(lags: { number }): string
	local counts: { number } = { 0, 0, 0 }
	for _, lag: number in lags do
		local at: number = math.min(lag, #counts - 1) + 1
		counts[at] += 1
	end

	local shares: string = `{share(counts[1], #lags)}/{share(counts[2], #lags)}/{share(counts[3], #lags)}`

	return `foot lag 0/1/2+ steps {shares} of {#lags} reads`
end

--[[
    P8's clause: the off arm's span, then each arm's added time against the
    off arm's p50, its solves, writes and wall at p50 over the steps every
    worker reached, its writes done in their step, its early starts and its
    foot's lag
--]]

function Lines.bend(rigs: number, off: Arm, arms: { Arm }): string
	local base: number = Frames.percentile(off.spans, P50)
	local offHigh: number = Frames.percentile(off.spans, P95)
	local clauses: { string } = {
		`P8 over {rigs} stand-ins, every leg bent each step, times a step summed over its workers`,
		string.format(
			"off span p50 %.3f p95 %.3f ms over %d steps",
			base * MILLISECONDS,
			offHigh * MILLISECONDS,
			#off.spans
		),
	}

	for _, arm: Arm in arms do
		local name: string = arm.workers == 0 and "serial" or Lines.named(arm.workers)
		local added: string = string.format(
			"added p50 %.3f p95 %.3f ms",
			(Frames.percentile(arm.spans, P50) - base) * MILLISECONDS,
			(Frames.percentile(arm.spans, P95) - base) * MILLISECONDS
		)

		local parts: string = string.format(
			"compute p50 %.3f ms, writes p50 %.3f ms, wall p50 %.3f ms over %d steps",
			Frames.percentile(arm.computes, P50) * MILLISECONDS,
			Frames.percentile(arm.writes, P50) * MILLISECONDS,
			Frames.percentile(arm.walls, P50) * MILLISECONDS,
			#arm.walls
		)

		local timely: string = `in step {share(arm.inStep, arm.callbacks)} of {arm.callbacks}, {arm.early} early`
		table.insert(clauses, `{name} {added}, {parts}, {timely}, {footOf(arm.lags)}`)
	end

	return table.concat(clauses, SEPARATOR)
end

--[[
    How many steps behind the latest the foot shows, from its height above
    its rest: the nearest of the rise's values gives the step it was bent
    for, counted round the rise's cycle, so a lag of a whole cycle reads 0
--]]

function Lines.lag(height: number, latest: number, rise: Rise): number
	local shown: number = math.round((height - rise.base) / rise.spacing) % rise.count

	return (latest - shown) % rise.count
end

--[[
    A probe's line: the player, then its clauses, then what stopped it
    when something did, cut to what clientCost carries
--]]

function Lines.line(player: string, clauses: { string }, failure: string?): string
	local body: string = table.concat(clauses, SEPARATOR)
	if failure and #clauses > 0 then
		body = `{body}{SEPARATOR}then {failure}`
	elseif failure then
		body = failure
	end

	return string.sub(`{player}: {body}`, 1, LINE_BYTES)
end

return Lines
