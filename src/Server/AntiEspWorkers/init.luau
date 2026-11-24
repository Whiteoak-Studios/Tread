--[[
    Anti-ESP's rays on Actor workers, the main thread's side: a slice's due
    pairs packed round robin for the workers idle at its start, sent at its
    end, and each batch landed at the next slice, or its pairs made due again
--]]

--!strict
--!native
local Casts = require(script.Casts)
local Pool = require(script.Parent.RelayWorkers.Pool)

local FOLDER: string = "TreadAntiEspWorkers" -- The folder under ServerScriptService the workers are cloned into
local GROWTH: number = 2 -- How many times larger a worker's packing buffer grows once a batch outgrows it
local HEADER_BYTES: number = Casts.HEADER_BYTES
local BOX_BYTES: number = Casts.BOX_BYTES
local RESULT_BYTES: number = Casts.RESULT_BYTES

type Pool = Pool.Pool

--[[
    What hands back one pair of a batch: the pair, the stamp it was packed
    under, whether a ray of its test was open, nil when it must be made due
    again untested, how many rays the worker cast for it, the schedule's
    clock it settles on, the reach of the slice that packed it, and the box
    a learner sent back, in a buffer the next call reuses
--]]

export type Land = (pair: number, stamp: number, open: boolean?, rays: number, reach: number, box: buffer?) -> ()

local Running: Pool? = nil
local Count: number = 0
local FailOpen: number = 0 -- Seconds after its send a batch is given up, back or not
local Shared: buffer = buffer.create(0) -- What each batch is sent beside, since a worker's run takes two buffers
local Box: buffer = buffer.create(BOX_BYTES) -- The box a landing pair sent back, copied out of its results

-- Each worker's by its index: what is packed for its next batch, which stays its batch while that is out
local Packed: { buffer } = {} -- Its first HEADER_BYTES kept for the count, grown once a batch outgrows it, and reused
local Used: { number } = {} -- The bytes of it packed
local PairsOf: { { number } } = {} -- Its batch's pairs in the order packed, each one's stamp and its count of rays
local StampsOf: { { number } } = {}
local RaysOf: { { number } } = {}
local Sizes: { number } = {} -- The pairs in its batch
local Out: { boolean } = {} -- Whether its batch is out and not yet landed
local Lost: { boolean } = {} -- Whether that batch was given up while out, so its pairs were made due again
local Failed: { boolean } = {} -- Whether a batch of its landed as failure text, after which it is sent nothing
local SentIn: { number } = {} -- The slice its batch out was sent in, which is the batch's round
local SentAt: { number } = {} -- And the schedule's clock then
local Reaches: { number } = {} -- And that slice's reach, the clock its results settle on

-- The ready workers with nothing out at this slice's collect, which its pairs go to in turn
local Idle: { number } = {}
local IdleCount: number = 0
local Turn: number = 1 -- The place in Idle the next pair goes to

-- Since AntiEspWorkers.figures last gave them
local Tests: number = 0 -- The pairs of the batches that landed with results
local Busy: number = 0 -- Seconds the landed batches took their workers, summed
local Longest: number = 0 -- And the longest of them
local Late: number = 0 -- Batches not back by the slice after their own, given up past FailOpen, or failed

local AntiEspWorkers = {}

--[[
    Starts count workers in FOLDER under ServerScriptService, each casting
    against a copy of the include list as it stands now, whose batches out
    past failOpen seconds are given up. It runs once
--]]

function AntiEspWorkers.start(count: number, include: { Instance }, failOpen: number)
	if Running then
		error("AntiEspWorkers.start runs once, and it has already run", 2)
	elseif type(count) ~= "number" or not (count >= 1 and count % 1 == 0 and count < math.huge) then
		error(`AntiEspWorkers.start takes a whole number of workers from 1, not {count}`, 2)
	elseif type(include) ~= "table" then
		error(`AntiEspWorkers.start takes the include list as a table, not a {typeof(include)}`, 2)
	elseif type(failOpen) ~= "number" or not (failOpen > 0 and failOpen < math.huge) then
		error(`AntiEspWorkers.start takes the fail-open time in seconds above 0, not {failOpen}`, 2)
	end

	-- Copied now, as the main thread's own query takes its list at start, since the setup crosses only once ready
	local settings: Casts.Settings = { include = table.clone(include) }
	Running = Pool.new(count, FOLDER, script.Casts, settings)
	Count = count
	FailOpen = failOpen

	for worker: number = 1, count do
		Packed[worker] = buffer.create(HEADER_BYTES)
		Used[worker] = HEADER_BYTES
		PairsOf[worker] = {}
		StampsOf[worker] = {}
		RaysOf[worker] = {}
		Sizes[worker] = 0
		Out[worker] = false
		Lost[worker] = false
		Failed[worker] = false
		SentIn[worker] = 0
		SentAt[worker] = 0
		Reaches[worker] = 0
	end
end

--[[
    Hands every pair a worker's batch holds back to land, to be made due
    again untested, with the rays its results show the worker cast for it,
    or none when no results came back
--]]

local function requeue(land: Land, worker: number, results: buffer?)
	local pairs: { number } = PairsOf[worker]
	local stamps: { number } = StampsOf[worker]
	local rays: { number } = RaysOf[worker]
	local reach: number = Reaches[worker]

	for place: number = 1, Sizes[worker] do
		local cast: number = 0
		if results then
			cast = Casts.opened(results, place)
			if cast == 0 then
				cast = rays[place]
			end
		end

		land(pairs[place], stamps[place], nil, cast, reach)
	end
end

--[[
    Hands each pair of a landed batch's results to land, its rays the open
    one's place, or every ray when none was, with the box it sent back
--]]

local function hand(land: Land, worker: number, results: buffer)
	local pairs: { number } = PairsOf[worker]
	local stamps: { number } = StampsOf[worker]
	local rays: { number } = RaysOf[worker]
	local reach: number = Reaches[worker]
	local size: number = Sizes[worker]
	local boxAt: number = size * RESULT_BYTES -- The first box, past every pair's result

	for place: number = 1, size do
		local open: number = Casts.opened(results, place)
		if open > 0 then
			land(pairs[place], stamps[place], true, open, reach)
		elseif Casts.boxed(results, place) then
			buffer.copy(Box, 0, results, boxAt, BOX_BYTES)
			boxAt += BOX_BYTES
			land(pairs[place], stamps[place], false, rays[place], reach, Box)
		else
			land(pairs[place], stamps[place], false, rays[place], reach)
		end
	end
end

--[[
    Brings in what the workers did since the last slice, at the schedule's
    clock now. A batch back is handed to land a pair at a time in the order
    it was packed, unless it was sent longer ago than the fail-open time or
    landed as failure text, when its pairs are handed back to be made due
    again, as are those of a batch not back by this slice, the one after its
    own. A worker that failed is sent nothing more, with one warn. Gives how
    many ready workers have nothing out, which this slice's pairs go to
--]]

function AntiEspWorkers.collect(land: Land, now: number): number
	local pool: Pool? = Running
	if not pool then
		error("AntiEspWorkers.collect ran before AntiEspWorkers.start", 2)
	end

	-- Sends each newly bound worker its setup, without which it is never ready
	pool:ready()

	IdleCount = 0
	Turn = 1

	for worker: number = 1, Count do
		if Out[worker] then
			local results: buffer?, failure: string? = pool:landed(worker, SentIn[worker])

			if results ~= nil or failure ~= nil then
				local start: number, finish: number = pool:times(worker)
				local took: number = finish - start
				Busy += took
				Longest = math.max(Longest, took)
				Out[worker] = false

				if results then
					Tests += Sizes[worker]
				end

				if failure ~= nil then
					if not Lost[worker] then
						Late += 1
					end

					requeue(land, worker, nil)
					Failed[worker] = true

					local failed: string = `Anti-ESP worker {worker} in {FOLDER} landed failure text`
					warn(`{failed}, so its pairs are tested again and it is sent nothing more: {failure}`)
				elseif Lost[worker] or now - SentAt[worker] > FailOpen then
					-- Too old to apply, whose pairs a fresh test now answers, its rays still counted
					if not Lost[worker] then
						Late += 1
					end

					requeue(land, worker, results)
				elseif results then
					hand(land, worker, results)
				end

				Lost[worker] = false
				Sizes[worker] = 0
			elseif not Lost[worker] then
				-- Not back by the slice after its own, so its pairs are tested again now, and its results, should they
				-- come back, are not applied, since its pairs' stamps move on as they go due
				Lost[worker] = true
				Late += 1
				requeue(land, worker, nil)
			end
		elseif Sizes[worker] > 0 then
			-- Packed by a slice that threw before it sent, so its pairs go back to wait
			requeue(land, worker, nil)
			Sizes[worker] = 0
			Used[worker] = HEADER_BYTES
		end

		if not Out[worker] and not Failed[worker] and pool:isReady(worker) then
			IdleCount += 1
			Idle[IdleCount] = worker
		end
	end

	return IdleCount
end

--[[
    Packs one due pair's test for the next idle worker in turn: the pair,
    the stamp it was packed under and its first count rays, each as its
    origin and the direction from it to its end, as the main thread casts
    them. A pair that learns may come back with the box that blocked it
--]]

function AntiEspWorkers.add(
	pair: number,
	stamp: number,
	count: number,
	origins: { vector },
	ends: { vector },
	learn: boolean?
)
	if IdleCount == 0 then
		error("AntiEspWorkers.add has no idle worker to pack for, as this slice's collect found none", 2)
	end

	-- Whiteoak TODO: a slice packs every due pair it reaches for the workers idle at its collect, so with one idle
	-- that one takes the whole slice's batch; a cap on a batch's pairs, the rest cast in process, would bound how
	-- late a batch can come back, once a live run shows the skew
	local worker: number = Idle[Turn]
	Turn = Turn % IdleCount + 1

	local at: number = Used[worker]
	local size: number = at + Casts.pairSize(count)
	local packed: buffer = Packed[worker]

	if size > buffer.len(packed) then
		local grown: buffer = buffer.create(math.max(size, buffer.len(packed) * GROWTH))
		buffer.copy(grown, 0, packed, 0, at)
		packed = grown
		Packed[worker] = grown
	end

	local place: number = Sizes[worker] + 1
	Used[worker] = Casts.writePair(packed, at, count, origins, ends, learn)
	Sizes[worker] = place
	PairsOf[worker][place] = pair
	StampsOf[worker][place] = stamp
	RaysOf[worker][place] = count
end

--[[
    Sends each idle worker packed for this slice its batch, with the slice
    as its round, at the schedule's clock now, with the slice's reach its
    results settle on, which keeps it out until the batch lands or is given
    up. A worker packed nothing is sent nothing
--]]

function AntiEspWorkers.send(slice: number, now: number, reach: number)
	local pool: Pool? = Running
	if not pool then
		error("AntiEspWorkers.send ran before AntiEspWorkers.start", 2)
	end

	for index: number = 1, IdleCount do
		local worker: number = Idle[index]
		local pairs: number = Sizes[worker]

		if pairs > 0 then
			pool:send(worker, slice, Shared, Casts.batch(Packed[worker], Used[worker], pairs))

			Out[worker] = true
			SentIn[worker] = slice
			SentAt[worker] = now
			Reaches[worker] = reach
			Used[worker] = HEADER_BYTES
		end
	end

	IdleCount = 0
end

--[[
    Since the last call: the pair tests in batches that landed with
    results, the seconds those batches and the failed ones took their
    workers, summed, and the longest of them, and the late batches
--]]

function AntiEspWorkers.figures(): (number, number, number, number)
	local tests: number, busy: number, longest: number, late: number = Tests, Busy, Longest, Late
	Tests = 0
	Busy = 0
	Longest = 0
	Late = 0

	return tests, busy, longest, late
end

return AntiEspWorkers
