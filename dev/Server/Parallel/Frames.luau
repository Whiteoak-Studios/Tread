--[[
    ParallelFrames' probe: rounds handed to Actors at PreSimulation or
    PostSimulation, by message or a ConnectParallel callback, the frame
    event each one's results were first all readable at, and its lines
--]]

--!strict
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Pool = require(ServerScriptService.Server.Parallel.Pool)
local Timings = require(ServerScriptService.Server.Parallel.Timings)
local Work = require(ServerScriptService.Server.Parallel.Work)

local WORKERS: number = require(ServerScriptService.Server.Config.Parallel).frames.workers
local ROUNDS: number = require(ServerScriptService.Server.Config.Parallel).frames.rounds
local SPINS_MS: { number } = require(ServerScriptService.Server.Config.Parallel).frames.spinsMs
local ARMED_WAIT: number = require(ServerScriptService.Server.Config.Parallel).frames.armedWait
local ROUND_WAIT: number = require(ServerScriptService.Server.Config.Parallel).frames.roundWait
local ARM_WAIT: number = require(ServerScriptService.Server.Config.Parallel).frames.armWait
local MILLISECONDS: number = 1000
local PREFIX: string = "ParallelFrames" -- What each of the probe's lines begins with
local HEARTBEAT: string = "Heartbeat" -- The frame event that ends a frame
local MESSAGE: string = "message" -- An arm's wake when its workers take each round by message
local NONE: string = "none" -- A baseline arm's wake, which hands nothing out
local LATER: string = "later or never" -- Where a round in none of its arm's columns is counted
local SENDS: number = 2 -- The frame events a round is handed out at, a frame's first two
local LIST_SEPARATOR: string = ", "
local CLAUSE_SEPARATOR: string = "; "

-- The frame events the probe stamps in a frame's order, which a frame that runs as expected fires once each
local FRAME: { string } = { "PreSimulation", "PostSimulation", HEARTBEAT }

-- Where a round's results may first be all in: the frame counted from its send's, 0 for that one, and the event there
local COLUMNS: { Column } = {
	{ label = "the same PostSimulation", frame = 0, event = "PostSimulation" },
	{ label = "the same Heartbeat", frame = 0, event = HEARTBEAT },
	{ label = "the next PreSimulation", frame = 1, event = "PreSimulation" },
	{ label = "the next PostSimulation", frame = 1, event = "PostSimulation" },
	{ label = "the next Heartbeat", frame = 1, event = HEARTBEAT },
}

-- One arm of the probe
export type Arm = {
	send: string, -- The frame event the main thread hands each round out at
	wake: string, -- What wakes the workers: a message, the frame event their ConnectParallel callback is on, or none
	spin: number, -- Milliseconds each worker spins a round
}

-- One round as the main thread saw it
export type Round = {
	sent: number, -- os.clock() just before its hand-off
	at: number, -- Where in the arm's log the event it was handed out at stands
	seen: { number }, -- The workers' results readable at each event after the send, the first at at + 1
	starts: { number }, -- Each worker's start by its own os.clock(), read once all were in, empty when never
	finishes: { number },
}

-- How many of an arm's rounds were first all in at one column
export type Count = {
	label: string,
	count: number,
}

-- One arm's figures, every time in seconds
export type Measured = {
	sent: number, -- Rounds handed out
	counts: { Count }, -- In the line's order, the rounds later or never in last
	starts: { number }, -- Each round all in, its first worker's start less its send
	finishes: { number }, -- And its last worker's finish less its send
	heartbeats: { number }, -- Each round's send to the Heartbeat that ended its frame
	frames: { number }, -- Each round's frame, from the Heartbeat before its send to the one after
	early: number, -- Rounds all in with a worker's start before the send, which only a second clock gives
	odd: number, -- The arm's frames that didn't fire PreSimulation, PostSimulation and Heartbeat once each in that order
}

type Column = {
	label: string,
	frame: number,
	event: string,
}

local Frames = {}

-- Where the event stands in a frame's order, 0 for one the probe doesn't stamp
local function positionOf(event: string): number
	return table.find(FRAME, event) or 0
end

-- The first Heartbeat in the log from that index on, going by step, nil when the log has none that way
local function heartbeatFrom(kinds: { string }, from: number, step: number): number?
	local index: number = from
	while kinds[index] ~= nil do
		if kinds[index] == HEARTBEAT then
			return index
		end

		index += step
	end

	return nil
end

-- How many of the workers have connected their frame callback
local function armed(actors: { Actor }): number
	local count: number = 0
	for _, actor: Actor in actors do
		if actor:GetAttribute(Work.ARMED) == true then
			count += 1
		end
	end

	return count
end

-- The arms in the order the probe runs them: a baseline at each send event, then every worker arm at each spin
function Frames.arms(): { Arm }
	local arms: { Arm } = {}
	for position: number = 1, SENDS do
		table.insert(arms, { send = FRAME[position], wake = NONE, spin = 0 })
	end

	-- A callback on an event before the send's would only take the round a frame later, so none is run
	for _, spin: number in SPINS_MS do
		for position: number = 1, SENDS do
			local send: string = FRAME[position]
			table.insert(arms, { send = send, wake = MESSAGE, spin = spin })

			for woken: number = position, #FRAME do
				table.insert(arms, { send = send, wake = FRAME[woken], spin = spin })
			end
		end
	end

	return arms
end

-- An arm's name, as its line and its problems give it
function Frames.name(arm: Arm): string
	if arm.wake == NONE then
		return `{arm.send} baseline`
	end

	local woken: string = arm.wake == MESSAGE and "a message" or `a {arm.wake} ConnectParallel`

	return `{arm.send} send woken by {woken} at {arm.spin} ms`
end

-- The columns an arm handing out at that event shows, leaving out those of the send's own frame at or before its event
function Frames.columns(send: string): { Column }
	local shown: { Column } = {}
	for _, column: Column in COLUMNS do
		if column.frame > 0 or positionOf(column.event) > positionOf(send) then
			table.insert(shown, column)
		end
	end

	return shown
end

--[[
    The label of the column a round's results were first all in at: the
    first event after its send at which every worker's was readable, by
    the Heartbeats between and its kind, or later or never for a round
    with none such, or one in none of the columns given
--]]

function Frames.landing(kinds: { string }, round: Round, workers: number, columns: { Column }): string
	local frame: number = 0

	for offset: number, count: number in round.seen do
		local event: string = kinds[round.at + offset]
		if count >= workers then
			for _, column: Column in columns do
				if column.frame == frame and column.event == event then
					return column.label
				end
			end

			return LATER
		end

		if event == HEARTBEAT then
			frame += 1
		end
	end

	return LATER
end

-- An arm's rounds counted by the column each was first all in at, in the order its line gives them
function Frames.tally(kinds: { string }, rounds: { Round }, workers: number, send: string): { Count }
	local columns: { Column } = Frames.columns(send)
	local counts: { [string]: number } = { [LATER] = 0 }
	for _, column: Column in columns do
		counts[column.label] = 0
	end

	for _, round: Round in rounds do
		local label: string = Frames.landing(kinds, round, workers, columns)
		counts[label] += 1
	end

	local tallied: { Count } = {}
	for _, column: Column in columns do
		table.insert(tallied, { label = column.label, count = counts[column.label] })
	end

	table.insert(tallied, { label = LATER, count = counts[LATER] })

	return tallied
end

-- The log's frames after its first Heartbeat that didn't fire PreSimulation, PostSimulation and Heartbeat in turn
function Frames.odd(kinds: { string }): number
	local first: number? = table.find(kinds, HEARTBEAT)
	if not first then
		return 0
	end

	local odd: number = 0
	local position: number = 0
	local expected: boolean = true

	for index: number = first + 1, #kinds do
		local event: string = kinds[index]
		position += 1

		if FRAME[position] ~= event then
			expected = false
		end

		if event == HEARTBEAT then
			if not expected then
				odd += 1
			end

			position = 0
			expected = true
		end
	end

	return odd
end

--[[
    An arm's figures from its log of frame events, their stamps and its
    rounds: where each round was first all in, its workers' first start
    and last finish from its send for those all in, and its send and its
    frame against the Heartbeats either side of it
--]]

function Frames.measure(arm: Arm, kinds: { string }, stamps: { number }, rounds: { Round }, workers: number): Measured
	local starts: { number } = {}
	local finishes: { number } = {}
	local heartbeats: { number } = {}
	local frames: { number } = {}
	local early: number = 0

	for _, round: Round in rounds do
		if #round.starts > 0 then
			local first: number = math.huge
			local last: number = -math.huge
			for worker: number, start: number in round.starts do
				first = math.min(first, start)
				last = math.max(last, round.finishes[worker])
			end

			table.insert(starts, first - round.sent)
			table.insert(finishes, last - round.sent)

			if first < round.sent then
				early += 1
			end
		end

		local closing: number? = heartbeatFrom(kinds, round.at + 1, 1)
		local opening: number? = heartbeatFrom(kinds, round.at - 1, -1)
		if closing then
			table.insert(heartbeats, stamps[closing] - round.sent)

			if opening then
				table.insert(frames, stamps[closing] - stamps[opening])
			end
		end
	end

	return {
		sent = #rounds,
		counts = Frames.tally(kinds, rounds, workers, arm.send),
		starts = starts,
		finishes = finishes,
		heartbeats = heartbeats,
		frames = frames,
		early = early,
		odd = Frames.odd(kinds),
	}
end

-- An arm's line with nothing judged, its times p50 and p95 in ms by nearest rank, a baseline's without its workers'
function Frames.line(arm: Arm, measured: Measured): string
	local head: string = `{PREFIX} {Frames.name(arm)}: {measured.sent} rounds`
	local heartbeat: string = `to that frame's Heartbeat {Timings.spread(measured.heartbeats)}`
	local frame: string = `frame {Timings.spread(measured.frames)}`

	if arm.wake == NONE then
		local clauses: { string } =
			{ `{head}, nothing handed out`, `send {heartbeat}`, frame, `{measured.odd} odd frames` }

		return table.concat(clauses, CLAUSE_SEPARATOR)
	end

	local counted: { string } = {}
	for _, count: Count in measured.counts do
		table.insert(counted, `{count.label} {count.count}`)
	end

	local landed: string = `all in at {table.concat(counted, LIST_SEPARATOR)}`
	local start: string = `send to first start {Timings.spread(measured.starts)}`
	local times: string = `{start}, to last finish {Timings.spread(measured.finishes)}, {heartbeat}`
	local flags: string = `{measured.early} started before their send, {measured.odd} odd frames`

	return table.concat({ head, landed, times, frame, flags }, CLAUSE_SEPARATOR)
end

--[[
    One arm, on clones of its own unless it is a baseline: ROUNDS rounds one
    at a time, each handed out at the arm's send event once a Heartbeat has
    passed, the store read at every frame event after until every result
    is in or ROUND_WAIT passes. It gives its figures and why it stopped
    short, nil when it didn't, and takes away every connection and clone
--]]

local function runArm(arm: Arm): (Measured, string?)
	local workers: number = arm.wake == NONE and 0 or WORKERS
	local spin: number = arm.spin / MILLISECONDS
	local kinds: { string } = {}
	local stamps: { number } = {}
	local rounds: { Round } = {}
	local connections: { RBXScriptConnection } = {}

	local signals: { [string]: RBXScriptSignal<number> } = {
		PreSimulation = RunService.PreSimulation,
		PostSimulation = RunService.PostSimulation,
		Heartbeat = RunService.Heartbeat,
	}

	local function body(actors: { Actor }): string?
		local store: SharedTable = SharedTable.new()
		store[Work.HANDED] = 0

		if arm.wake ~= NONE and arm.wake ~= MESSAGE then
			for _, actor: Actor in actors do
				actor:SendMessage(Work.WAKE, arm.wake, spin, store)
			end

			local ready: boolean = Pool.within(ARMED_WAIT, function (): boolean
				return armed(actors) == workers
			end)

			if not ready then
				return `{armed(actors)} of {workers} workers connected their {arm.wake} callback within {ARMED_WAIT} s`
			end
		end

		local flying: Round? = nil
		local started: boolean = false
		local finished: boolean = false
		local short: string? = nil
		local never: number = 0

		-- The next round handed to every worker from this serial handler, its send stamped just before
		local function send(index: number)
			local round: Round = { sent = 0, at = index, seen = {}, starts = {}, finishes = {} }
			table.insert(rounds, round)
			local handed: number = #rounds

			round.sent = os.clock()
			if arm.wake == MESSAGE then
				for _, actor: Actor in actors do
					actor:SendMessage(Work.HAND, handed, spin, store)
				end
			elseif arm.wake ~= NONE then
				store[Work.HANDED] = handed
			end

			flying = round
		end

		-- One frame event: stamped and logged, the round in flight read, then the next round handed out at the send event
		local function step(event: string)
			local now: number = os.clock()
			table.insert(kinds, event)
			table.insert(stamps, now)

			local round: Round? = flying
			if round then
				local count: number = Pool.landed(store, workers, #rounds)
				table.insert(round.seen, count)

				if count >= workers then
					for worker: number = 1, workers do
						local base: number = (worker - 1) * Work.FIELDS
						round.starts[worker] = store[base + Work.START]
						round.finishes[worker] = store[base + Work.FINISH]
					end

					flying = nil
				elseif now - round.sent >= ROUND_WAIT then
					never += 1
					flying = nil
				end
			end

			-- The arm ends at a Heartbeat, so the last round's frame has its end in the log
			if event == HEARTBEAT then
				started = true
				finished = flying == nil and #rounds >= ROUNDS
			elseif event == arm.send and started and flying == nil and #rounds < ROUNDS then
				send(#kinds)
			end
		end

		-- Each serial handler, disconnected once the pool is done, whether the arm ended or a wait for it did
		for _, event: string in FRAME do
			table.insert(
				connections,
				signals[event]:Connect(function ()
					if finished then
						return
					end

					local stepped: boolean, thrown: any = pcall(step, event)
					if not stepped then
						short = `its {event} handler threw: {thrown}`
						finished = true
					end
				end)
			)
		end

		local done: boolean = Pool.within(ARM_WAIT, function (): boolean
			return finished
		end)

		if not done then
			return `{#rounds} of {ROUNDS} rounds were handed out within {ARM_WAIT} s`
		elseif short then
			return short
		elseif never > 0 then
			return `{never} of {#rounds} rounds had a result unseen within {ROUND_WAIT} s`
		end

		return nil
	end

	local stopped: string? = nil
	if workers > 0 then
		stopped = Pool.with(workers, body)
	else
		local ran: boolean, result: any = pcall(body, {})
		stopped = result
		if not ran then
			stopped = `it threw: {result}`
		end
	end

	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	return Frames.measure(arm, kinds, stamps, rounds, workers), stopped
end

--[[
    Runs every arm in turn, each worker arm on clones of its own, and gives
    a line an arm with nothing judged and why any arm stopped short
--]]

function Frames.run(): ({ string }, { string })
	local lines: { string } = {}
	local problems: { string } = {}

	for _, arm: Arm in Frames.arms() do
		local measured: Measured, stopped: string? = runArm(arm)
		table.insert(lines, Frames.line(arm, measured))

		if stopped then
			table.insert(problems, `{Frames.name(arm)} stopped short: {stopped}`)
		end
	end

	return lines, problems
end

return Frames
