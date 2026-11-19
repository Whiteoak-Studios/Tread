--[[
    ParallelReturn's three probes on clones of the parallel worker: when
    results sent at a Heartbeat come back, what crosses between VMs and as
    what, and what sends and returns of each size cost, each giving lines
--]]

--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Pool = require(ServerScriptService.Server.Parallel.Pool)
local Summary = require(ServerScriptService.Server.Parallel.Summary)
local Timings = require(ServerScriptService.Server.Parallel.Timings)
local Work = require(ServerScriptService.Server.Parallel.Work)

local WORKERS: number = require(ServerScriptService.Server.Config.Parallel).returns.workers
local HEARTBEATS: number = require(ServerScriptService.Server.Config.Parallel).returns.heartbeats
local MAIN_MS: number = require(ServerScriptService.Server.Config.Parallel).returns.mainMs
local WORKER_MS: number = require(ServerScriptService.Server.Config.Parallel).returns.workerMs
local ROUNDS_WAIT: number = require(ServerScriptService.Server.Config.Parallel).returns.roundsWait
local DRAIN_WAIT: number = require(ServerScriptService.Server.Config.Parallel).returns.drainWait
local ECHO_KILOBYTES: number = require(ServerScriptService.Server.Config.Parallel).returns.echoKilobytes
local ECHO_BUFFERS: number = require(ServerScriptService.Server.Config.Parallel).returns.echoBuffers
local ECHO_WAIT: number = require(ServerScriptService.Server.Config.Parallel).returns.echoWait
local SEND_KILOBYTES: { number } = require(ServerScriptService.Server.Config.Parallel).returns.sendKilobytes
local SEND_WORKERS: { number } = require(ServerScriptService.Server.Config.Parallel).returns.sendWorkers
local RETURN_KILOBYTES: { number } = require(ServerScriptService.Server.Config.Parallel).returns.returnKilobytes
local PIECES: number = require(ServerScriptService.Server.Config.Parallel).returns.pieces
local REPEATS: number = require(ServerScriptService.Server.Config.Parallel).returns.repeats
local ROUND_WAIT: number = require(ServerScriptService.Server.Config.Parallel).returns.roundWait
local MILLISECONDS: number = 1000
local BYTES_PER_KILOBYTE: number = 1000
local SEPARATOR: string = ", " -- Between the parts of a P4 line's return

type Round = Timings.Round
type Beat = Timings.Beat

-- A P4 value to send, by the name its line gives it, and the line in place of a send when there is none
type Case = {
	label: string,
	value: any,
	absent: string?,
}

-- What came back for a P4 value: the worker's description of it, the event's refusal of it, and the value
type Answer = {
	arrived: string,
	failure: string?,
	value: any,
}

local Returns = {}

-- Copies the payload into the pieces end to end, each its own exact length
local function split(payload: buffer, pieces: { buffer })
	local offset: number = 0
	for _, piece: buffer in pieces do
		local length: number = buffer.len(piece)
		buffer.copy(piece, 0, payload, offset, length)
		offset += length
	end
end

-- PIECES buffers, made once a row, whose exact lengths hold that many bytes end to end
local function piecesOf(bytes: number): { buffer }
	local pieces: { buffer } = {}
	for _, length: number in Timings.lengths(bytes, PIECES) do
		table.insert(pieces, buffer.create(length))
	end

	return pieces
end

--[[
    Sends REPEATS rounds one at a time, the first from a Heartbeat and each
    later one from the Heartbeat that found the last one in, collecting
    each once it is in. It gives the rounds in and why it stopped short,
    nil when every round was in within its own ROUND_WAIT
--]]

local function drive(send: (number) -> (), landed: (number) -> boolean, collect: () -> ()): (number, string?)
	RunService.Heartbeat:Wait()

	for round: number = 1, REPEATS do
		send(round)

		local done: boolean = Pool.within(ROUND_WAIT, function (): boolean
			return landed(round)
		end)

		if not done then
			return round - 1, `round {round} of {REPEATS} was not in within {ROUND_WAIT} s`
		end

		collect()
	end

	return REPEATS, nil
end

-- A P4 value's line: what it arrived as, whether the buffer sent was copied, and what came back as what
local function echoed(case: Case, answer: Answer, original: buffer): string
	local into: string = `in as {answer.arrived}`
	if rawequal(case.value, original) then
		local copied: string = buffer.readu8(original, 0) == Work.MARK and "the buffer sent itself" or "a copy"
		into = `{into}, {copied}`
	end

	local failure: string? = answer.failure
	if failure then
		return `P4 {case.label}: {into}; the event refused it back: {failure}`
	end

	local back: any = answer.value
	local parts: { string } = { `back as {Work.describe(back)}` }

	-- Only a table, buffer or Instance sent can come back as the same object
	local kind: string = type(case.value)
	if kind == "table" or kind == "buffer" or kind == "userdata" then
		table.insert(parts, rawequal(back, case.value) and "the same object" or "a different object")
	end

	if type(back) == "buffer" and buffer.len(back) > 0 and buffer.readu8(back, 0) == Work.MARK then
		table.insert(parts, "carrying the worker's write")
	end

	return `P4 {case.label}: {into}; {table.concat(parts, SEPARATOR)}`
end

-- A P4 SharedTable write's line: the worker's refusal, or what the main thread read there
local function storedLine(name: string, refusal: string?, value: any): string
	if refusal then
		return `P4 SharedTable {name}: the worker's write was refused: {refusal}`
	end

	return `P4 SharedTable {name}: arrived as {Work.describe(value)}`
end

--[[
    P1: from one Heartbeat connection, WORKERS clones each sent a round at
    every Heartbeat after the main thread's busy loop, a deferred poll of
    the marks queued behind each send, beside one more clone running the
    ConnectParallel arm, and every PreSimulation counted as a frame. It
    gives its lines and why it stopped short
--]]

function Returns.timing(): ({ string }, { string })
	local rounds: { Round } = {}
	local beats: { Beat } = {}
	local heartbeats: { [number]: number } = {}
	local frame: number = 0
	local connections: { RBXScriptConnection } = {}

	local stopped: string? = Pool.with(WORKERS + 1, function (actors: { Actor }): string?
		local marks: SharedTable = SharedTable.new()
		marks[Work.FRAME] = frame

		-- Each worker's own event, whose connection ends as the pool destroys the event with its clone
		local events: { BindableEvent } = {}
		for worker: number = 1, WORKERS do
			local event: BindableEvent = Instance.new("BindableEvent")
			event.Parent = actors[worker]
			events[worker] = event

			event.Event:Connect(function (from: number, round: number, start: number, finish: number)
				local landed: number = os.clock()
				local entry: Round? = rounds[round]
				if entry then
					entry.starts[from] = start
					entry.finishes[from] = finish
					entry.arrivals[from] = frame
					entry.landed[from] = landed
				end
			end)
		end

		local arm: Actor = actors[WORKERS + 1]
		local armEvent: BindableEvent = Instance.new("BindableEvent")
		armEvent.Parent = arm

		armEvent.Event:Connect(function (parallel: number, read: number, synchronized: number)
			table.insert(beats, { parallel = parallel, frame = read, synchronized = synchronized, arrived = frame })
		end)

		-- Disconnected below with the Heartbeat's, once the rounds are in or a wait for them ends
		table.insert(
			connections,
			RunService.PreSimulation:Connect(function ()
				frame += 1
				marks[Work.FRAME] = frame
			end)
		)

		arm:SendMessage(Work.ARM, armEvent, marks)

		local finished: boolean = false
		local short: string? = nil

		-- One Heartbeat's round: the busy loop, then every worker sent the round from this serial phase, the poll queued
		local function send()
			heartbeats[frame] = os.clock()
			Work.busy(MAIN_MS / MILLISECONDS)

			local round: number = #rounds + 1
			local entry: Round = {
				frame = frame,
				sent = os.clock(),
				starts = {},
				finishes = {},
				arrivals = {},
				landed = {},
				polled = false,
			}

			rounds[round] = entry

			for worker: number = 1, WORKERS do
				actors[worker]:SendMessage(Work.TIMING, round, WORKER_MS / MILLISECONDS, events[worker], marks)
			end

			task.defer(function ()
				entry.polled = frame == entry.frame and Pool.landed(marks, WORKERS, round) == WORKERS
			end)
		end

		table.insert(
			connections,
			RunService.Heartbeat:Connect(function ()
				if finished then
					return
				elseif #rounds >= HEARTBEATS then
					finished = true
					return
				end

				local sent: boolean, thrown: any = pcall(send)
				if not sent then
					short = `a Heartbeat's round threw: {thrown}`
					finished = true
				end
			end)
		)

		local done: boolean = Pool.within(ROUNDS_WAIT, function (): boolean
			return finished
		end)

		if not done then
			return `{#rounds} of {HEARTBEATS} rounds were sent within {ROUNDS_WAIT} s`
		elseif short then
			return short
		end

		-- Late events, each from a round's slowest worker
		local drained: boolean = Pool.within(DRAIN_WAIT, function (): boolean
			return Timings.missing(rounds, WORKERS) == 0
		end)

		if not drained then
			local missing: number = Timings.missing(rounds, WORKERS)
			return `{missing} of {#rounds * WORKERS} events were not back within {DRAIN_WAIT} s of the last round`
		end

		return nil
	end)

	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	local sending: string = `one sent at each Heartbeat after a {MAIN_MS} ms busy loop`
	local head: string =
		`P1: {#rounds} rounds to {Summary.named(WORKERS)}, {sending}, each worker spinning {WORKER_MS} ms`
	local lines: { string } = Timings.timing(WORKERS, rounds, heartbeats, beats)
	table.insert(lines, 1, head)

	local problems: { string } = {}
	if stopped then
		table.insert(problems, `P1 stopped short: {stopped}`)
	end

	return lines, problems
end

--[[
    P4: each value sent to one clone through SendMessage, described as it
    arrived and fired back through its event from the parallel handler,
    then a buffer and a string written into a SharedTable from the clone's
    parallel handler. It gives a line a value and why it stopped short
--]]

function Returns.crossing(): ({ string }, { string })
	local lines: { string } = {}
	local problems: { string } = {}
	local bytes: number = ECHO_KILOBYTES * BYTES_PER_KILOBYTE

	local stopped: string? = Pool.with(1, function (actors: { Actor }): string?
		local actor: Actor = actors[1]
		local original: buffer = buffer.create(bytes)

		local buffers: { buffer } = {}
		for _ = 1, ECHO_BUFFERS do
			table.insert(buffers, buffer.create(bytes))
		end

		-- The values in the order the lines give them, the first real player's only when one is in
		local cases: { Case } = {
			{ label = "buffer", value = original },
			{ label = "table of buffers", value = buffers },
			{ label = "string", value = string.rep(Work.FILL, bytes) },
			{ label = "vector", value = vector.create(1, 2, 3) },
			{ label = "nested table", value = { list = { 1, 2, 3 }, inner = { deeper = { flag = true } } } },
			{ label = "player", value = Players:GetPlayers()[1], absent = "no real player is in the server to send" },
			{ label = "frozen table", value = table.freeze(setmetatable({ answer = 42 }, { __index = {} })) },
		}

		local answers: { [string]: Answer } = {}

		-- Its connection ends as the pool destroys the event with the clone
		local echoes: BindableEvent = Instance.new("BindableEvent")
		echoes.Parent = actor
		echoes.Event:Connect(function (label: string, arrived: string, failure: string?, value: any)
			answers[label] = { arrived = arrived, failure = failure, value = value }
		end)

		for _, case: Case in cases do
			if case.value == nil then
				table.insert(lines, `P4 {case.label}: {case.absent}`)
				continue
			end

			local sent: boolean, refusal: any = pcall(function ()
				actor:SendMessage(Work.ECHO, case.label, echoes, case.value)
			end)

			if not sent then
				table.insert(lines, `P4 {case.label}: SendMessage refused it: {refusal}`)
				continue
			end

			Pool.within(ECHO_WAIT, function (): boolean
				return answers[case.label] ~= nil
			end)

			local answer: Answer? = answers[case.label]
			if not answer then
				table.insert(problems, `P4 {case.label} had nothing back within {ECHO_WAIT} s`)
				continue
			end

			table.insert(lines, echoed(case, answer, original))
		end

		local store: SharedTable = SharedTable.new()
		local heard: boolean = false
		local bufferRefusal: string? = nil
		local textRefusal: string? = nil

		-- Its connection ends as the pool destroys the event with the clone
		local writes: BindableEvent = Instance.new("BindableEvent")
		writes.Parent = actor
		writes.Event:Connect(function (bufferFailure: string?, textFailure: string?)
			bufferRefusal = bufferFailure
			textRefusal = textFailure
			heard = true
		end)

		actor:SendMessage(Work.STORE, writes, store, bytes)

		local wrote: boolean = Pool.within(ECHO_WAIT, function (): boolean
			return heard
		end)

		if not wrote then
			table.insert(problems, `P4's SharedTable writes had nothing back within {ECHO_WAIT} s`)
			return nil
		end

		table.insert(lines, storedLine("buffer", bufferRefusal, store[Work.BUFFER]))
		table.insert(lines, storedLine("string", textRefusal, store[Work.TEXT]))

		return nil
	end)

	if stopped then
		table.insert(problems, `P4 stopped short: {stopped}`)
	end

	return lines, problems
end

--[[
    P5: payloads of each size sent through SendMessage to each count of
    clones, then returns of each size from one clone, by its event and as
    strings in the marks table, each copied into PIECES exact-length
    buffers. It gives a line a row and why any row stopped short
--]]

function Returns.sizes(): ({ string }, { string })
	local lines: { string } = {}
	local problems: { string } = {}

	local most: number = 0
	for _, count: number in SEND_WORKERS do
		most = math.max(most, count)
	end

	local stopped: string? = Pool.with(most, function (actors: { Actor }): string?
		for _, kilobytes: number in SEND_KILOBYTES do
			local payload: buffer = buffer.create(kilobytes * BYTES_PER_KILOBYTE)

			for _, count: number in SEND_WORKERS do
				local marks: SharedTable = SharedTable.new()
				local sends: { number } = {}
				local starts: { number } = {}
				local sent: number = 0

				local landed: number, short: string? = drive(function (round: number)
					sent = os.clock()
					for worker: number = 1, count do
						actors[worker]:SendMessage(Work.SEND, round, marks, payload)
					end

					table.insert(sends, os.clock() - sent)
				end, function (round: number): boolean
					return Pool.landed(marks, count, round) == count
				end, function ()
					for worker: number = 1, count do
						table.insert(starts, marks[(worker - 1) * Work.FIELDS + Work.START] - sent)
					end
				end)

				local row: string = `P5 send {kilobytes} KB to {Summary.named(count)}`
				local times: string = `send {Timings.spread(sends)}, worker start minus send {Timings.spread(starts)}`
				table.insert(lines, `{row}: {landed} of {REPEATS} rounds, {times}`)

				if short then
					table.insert(problems, `{row}: {short}`)
				end
			end
		end

		local actor: Actor = actors[1]

		for _, kilobytes: number in RETURN_KILOBYTES do
			local bytes: number = kilobytes * BYTES_PER_KILOBYTE
			local pieces: { buffer } = piecesOf(bytes)
			local marks: SharedTable = SharedTable.new()
			local fires: { number } = {}
			local arrivals: { number } = {}
			local copies: { number } = {}
			local arrived: { [number]: boolean } = {}

			-- The row's own event, destroyed after it, which ends its connection
			local event: BindableEvent = Instance.new("BindableEvent")
			event.Parent = actor
			event.Event:Connect(function (round: number, fired: number, returned: buffer)
				local at: number = os.clock()
				table.insert(arrivals, at - fired)

				split(returned, pieces)
				table.insert(copies, os.clock() - at)
				arrived[round] = true
			end)

			local landed: number, short: string? = drive(function (round: number)
				actor:SendMessage(Work.RETURN, round, bytes, event, marks)
			end, function (round: number): boolean
				return arrived[round] == true and Pool.landed(marks, 1, round) == 1
			end, function ()
				table.insert(fires, marks[Work.FINISH] - marks[Work.START])
			end)

			event:Destroy()

			local row: string = `P5 event return {kilobytes} KB`
			local fire: string = `the worker's Fire {Timings.spread(fires)}`
			local arrival: string = `arrival minus Fire {Timings.spread(arrivals)}`
			local copy: string = `copy into {PIECES} buffers {Timings.spread(copies)}`
			table.insert(lines, `{row}: {landed} of {REPEATS} rounds, {fire}, {arrival}, {copy}`)

			if short then
				table.insert(problems, `{row}: {short}`)
			end
		end

		for _, kilobytes: number in RETURN_KILOBYTES do
			local bytes: number = kilobytes * BYTES_PER_KILOBYTE
			local pieces: { buffer } = piecesOf(bytes)
			local marks: SharedTable = SharedTable.new()
			local writes: { number } = {}
			local seen: { number } = {}
			local reads: { number } = {}
			local copies: { number } = {}

			local landed: number, short: string? = drive(function (round: number)
				actor:SendMessage(Work.SHARE, round, bytes, marks)
			end, function (round: number): boolean
				return Pool.landed(marks, 1, round) == 1
			end, function ()
				local found: number = os.clock()
				local wrote: number = marks[Work.START]
				table.insert(writes, marks[Work.FINISH] - wrote)
				table.insert(seen, found - wrote)

				local began: number = os.clock()
				local text: string = marks[Work.TEXT]
				local read: number = os.clock()
				table.insert(reads, read - began)

				split(buffer.fromstring(text), pieces)
				table.insert(copies, os.clock() - read)
			end)

			local row: string = `P5 SharedTable return {kilobytes} KB`
			local write: string = `the worker's write {Timings.spread(writes)}`
			local sighting: string =
				`seen at a Heartbeat minus write {Timings.spread(seen)}, read {Timings.spread(reads)}`
			local copy: string = `copy into {PIECES} buffers {Timings.spread(copies)}`
			table.insert(lines, `{row}: {landed} of {REPEATS} rounds, {write}, {sighting}, {copy}`)

			if short then
				table.insert(problems, `{row}: {short}`)
			end
		end

		return nil
	end)

	if stopped then
		table.insert(problems, `P5 stopped short: {stopped}`)
	end

	return lines, problems
end

return Returns
