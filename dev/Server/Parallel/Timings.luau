--[[
    ParallelReturn's arithmetic: times as p50 and p95 in ms by nearest rank,
    shares, the lengths a return is cut into, and P1's lines from its rounds
    and its ConnectParallel arm's callbacks
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Summary = require(ServerScriptService.Server.Parallel.Summary)

local MILLISECONDS: number = 1000
local PERCENT: number = 100
local P50: number = 0.5
local P95: number = 0.95

-- One of P1's rounds, each worker's fields by its index and filled as its event arrives
export type Round = {
	frame: number, -- The main thread's PreSimulation count when it was sent
	sent: number, -- os.clock() just before its sends
	starts: { [number]: number }, -- Each worker's start by its own os.clock(), as its event brought it
	finishes: { [number]: number },
	arrivals: { [number]: number }, -- The PreSimulation count when each worker's event reached the main thread
	landed: { [number]: number }, -- os.clock() there
	polled: boolean, -- Whether the deferred poll behind the sends found every worker's round, in the frame it was sent
}

-- One callback of P1's ConnectParallel arm
export type Beat = {
	parallel: number, -- os.clock() as its parallel callback began
	frame: number, -- The PreSimulation count it read there
	synchronized: number, -- The count it read once synchronized
	arrived: number, -- The count when its event reached the main thread
}

local Timings = {}

-- p50 and p95 of the samples by nearest rank, in ms, leaving the list as it was
function Timings.spread(samples: { number }): string
	local sorted: { number } = table.clone(samples)
	local low: number = Summary.rank(sorted, P50) * MILLISECONDS
	local high: number = Summary.rank(sorted, P95) * MILLISECONDS

	return string.format("p50 %.3f ms p95 %.3f ms", low, high)
end

-- That count of the total as a percentage to a tenth, 0 for a total of none
function Timings.share(count: number, total: number): string
	local percent: number = 0
	if total > 0 then
		percent = PERCENT * count / total
	end

	return string.format("%.1f%%", percent)
end

-- The lengths of that many buffers that hold the bytes end to end, the first ones a byte longer when they don't divide
function Timings.lengths(bytes: number, count: number): { number }
	local lengths: { number } = table.create(count, bytes // count)
	for piece: number = 1, bytes % count do
		lengths[piece] += 1
	end

	return lengths
end

-- How many of the workers' events P1's rounds are still waiting for
function Timings.missing(rounds: { Round }, workers: number): number
	local missing: number = 0
	for _, round: Round in rounds do
		for worker: number = 1, workers do
			if round.arrivals[worker] == nil then
				missing += 1
			end
		end
	end

	return missing
end

--[[
    P1's lines: the rounds whose events were all in before the next
    PreSimulation, those the deferred poll saw, the workers' starts and
    finishes after the send, and the arm's callbacks in the rounds' frames,
    each beside that frame's main Heartbeat start, which heartbeats holds
--]]

function Timings.timing(
	workers: number,
	rounds: { Round },
	heartbeats: { [number]: number },
	beats: { Beat }
): { string }
	local inFrame: number = 0
	local complete: number = 0
	local polled: number = 0
	local lasts: { number } = {}
	local starts: { number } = {}
	local finishes: { number } = {}

	for _, round: Round in rounds do
		local arrived: number = 0
		local same: number = 0
		local last: number = -math.huge

		for worker: number = 1, workers do
			local arrival: number? = round.arrivals[worker]
			if arrival then
				arrived += 1
				last = math.max(last, round.landed[worker])
				table.insert(starts, round.starts[worker] - round.sent)
				table.insert(finishes, round.finishes[worker] - round.sent)

				if arrival == round.frame then
					same += 1
				end
			end
		end

		if arrived == workers then
			complete += 1
			table.insert(lasts, last - round.sent)
		end

		if same == workers then
			inFrame += 1
		end

		if round.polled then
			polled += 1
		end
	end

	-- The rounds' frames, first to last, none with no round
	local first: number = 0
	local final: number = -1
	if #rounds > 0 then
		first = rounds[1].frame
		final = rounds[#rounds].frame
	end

	local frames: number = final - first + 1
	local heard: number = 0
	local synchronized: number = 0
	local onMain: number = 0
	local offsets: { number } = {}

	for _, beat: Beat in beats do
		if beat.frame >= first and beat.frame <= final then
			heard += 1

			if beat.synchronized == beat.frame then
				synchronized += 1
			end

			if beat.arrived == beat.frame then
				onMain += 1
			end

			local heartbeat: number? = heartbeats[beat.frame]
			if heartbeat then
				table.insert(offsets, beat.parallel - heartbeat)
			end
		end
	end

	local total: number = #rounds
	local before: string = `{inFrame} of {total} rounds ({Timings.share(inFrame, total)})`
	local events: string = `P1 events: {before} had all {workers} in before the next PreSimulation`
	local all: string = `{complete} had all {workers} in at all`
	local tail: string = `the last one's arrival minus send {Timings.spread(lasts)}, over {frames} PreSimulations`

	local saw: string = `{polled} of {total} rounds ({Timings.share(polled, total)})`
	local poll: string = `P1 deferred poll: {saw} found every worker's round in the frame it was sent`

	local start: string = `start minus send {Timings.spread(starts)}`
	local work: string = `P1 workers: {start}, finish minus send {Timings.spread(finishes)}, over {#starts} events`

	local offset: string = `parallel start minus that frame's main Heartbeat {Timings.spread(offsets)} over {#offsets}`
	local inSync: string = `synchronized in that frame {synchronized} ({Timings.share(synchronized, heard)})`
	local inMain: string = `on the main thread in that frame {onMain} ({Timings.share(onMain, heard)})`
	local arm: string = `P1 ConnectParallel arm: {heard} callbacks over {frames} frames, {offset}, {inSync}, {inMain}`

	return { `{events} and {all}, {tail}`, poll, work, arm }
end

return Timings
