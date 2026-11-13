--[[
    The parallel probes' workers: clones of the worker template in their own
    folder for as long as a probe needs them, and ParallelProbe's loop sized
    and timed serially, then sent one batch a Heartbeat until all are in
--]]

--!strict
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Summary = require(ServerScriptService.Server.Parallel.Summary)
local Work = require(ServerScriptService.Server.Parallel.Work)

-- The Actor every worker is cloned from, which never works itself
local Template = ServerScriptService.Server.Parallel.Worker

local REPEATS: number = require(ServerScriptService.Server.Config.Parallel).repeats
local WORK_MS: number = require(ServerScriptService.Server.Config.Parallel).workMs
local BYTES: number = require(ServerScriptService.Server.Config.Parallel).bytes
local TRIAL_PASSES: number = require(ServerScriptService.Server.Config.Parallel).trialPasses
local TRIALS: number = require(ServerScriptService.Server.Config.Parallel).trials
local READY_WAIT: number = require(ServerScriptService.Server.Config.Parallel).readyWait
local BATCH_WAIT: number = require(ServerScriptService.Server.Config.Parallel).batchWait
local RUN_WAIT: number = require(ServerScriptService.Server.Config.Parallel).runWait
local MILLISECONDS: number = 1000
local HOME: string = "ParallelProbe" -- The clones' folder under ServerScriptService

type Batch = Summary.Batch

local Pool = {}

-- How many of the workers have bound their topics
local function bound(actors: { Actor }): number
	local count: number = 0
	for _, actor: Actor in actors do
		if actor:GetAttribute(Work.BOUND) == true then
			count += 1
		end
	end

	return count
end

-- How many of the first that many workers' marks show the round
function Pool.landed(marks: SharedTable, workers: number, round: number): number
	local count: number = 0
	for worker: number = 1, workers do
		if marks[(worker - 1) * Work.FIELDS + Work.ROUND] == round then
			count += 1
		end
	end

	return count
end

-- The batch in the marks, sent at that os.clock(), and whether it was in at the Heartbeat after the send
local function batchOf(marks: SharedTable, workers: number, sent: number, byNext: boolean): Batch
	local starts: { number } = table.create(workers, 0)
	local finishes: { number } = table.create(workers, 0)

	for worker: number = 1, workers do
		local base: number = (worker - 1) * Work.FIELDS
		starts[worker] = marks[base + Work.START]
		finishes[worker] = marks[base + Work.FINISH]
	end

	return { sent = sent, starts = starts, finishes = finishes, byNext = byNext }
end

-- Waits a Heartbeat at a time until the check passes, giving whether it passed before that many seconds were up
function Pool.within(seconds: number, check: () -> boolean): boolean
	local by: number = os.clock() + seconds
	while not check() do
		if os.clock() >= by then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

--[[
    Clones that many workers into their folder under ServerScriptService,
    waits for each to bind its topics, then runs the body with them. It
    gives why it stopped short, the body's own reason or a throw, nil when
    it didn't, and takes away every clone whatever happened
--]]

function Pool.with(workers: number, body: ({ Actor }) -> string?): string?
	local folder: Folder = Instance.new("Folder")
	folder.Name = HOME

	local actors: { Actor } = {}
	for index: number = 1, workers do
		local actor: Actor = Template:Clone()
		actor.Name = `Worker{index}`
		actor:SetAttribute(Work.WORKER, index)
		actor.Parent = folder
		table.insert(actors, actor)
	end

	-- Parented last, so every clone finds its index as its script starts
	folder.Parent = ServerScriptService

	local ran: boolean, result: any = pcall(function (): string?
		-- A message sent before a worker binds its topics is never taken, so none goes until every one has
		local ready: boolean = Pool.within(READY_WAIT, function (): boolean
			return bound(actors) == workers
		end)

		if not ready then
			return `{bound(actors)} of {workers} workers bound their topics within {READY_WAIT} s`
		end

		return body(actors)
	end)

	-- Ends every clone's script, the bindings its Actor holds, and the events under it with their connections
	folder:Destroy()

	if not ran then
		return `it threw: {result}`
	end

	return result
end

--[[
    Sizes the loop to about WORK_MS on this server, from the fastest of
    TRIALS timed runs of TRIAL_PASSES passes, then times it REPEATS times
    run serially on the main thread. It gives the passes and each run's
    seconds, and errors when the sizing runs took no time to measure
--]]

function Pool.serial(): (number, { number })
	local data: buffer = buffer.create(BYTES)
	local fastest: number = math.huge

	for _ = 1, TRIALS do
		local began: number = os.clock()
		Work.spin(data, TRIAL_PASSES)
		fastest = math.min(fastest, os.clock() - began)
	end

	if not (fastest > 0 and fastest < math.huge) then
		error(`{TRIALS} sizing runs of {TRIAL_PASSES} passes gave no time to size the loop by`, 0)
	end

	local passes: number = math.max(1, math.round(TRIAL_PASSES * WORK_MS / MILLISECONDS / fastest))
	local times: { number } = table.create(REPEATS, 0)

	for run: number = 1, REPEATS do
		local began: number = os.clock()
		Work.spin(data, passes)
		times[run] = os.clock() - began
	end

	return passes, times
end

--[[
    From one Heartbeat connection, sends that many workers the batch at one
    Heartbeat and collects it at a later one, until REPEATS batches are in.
    It gives the batches in and why it stopped short, nil when it didn't,
    and takes away the connection and every clone whatever happened
--]]

function Pool.run(workers: number, passes: number): ({ Batch }, string?)
	local batches: { Batch } = {}
	local connection: RBXScriptConnection? = nil

	local stopped: string? = Pool.with(workers, function (actors: { Actor }): string?
		local marks: SharedTable = SharedTable.new()
		local round: number = 0 -- The batch in flight, or the last one in
		local flying: boolean = false
		local beat: number = 0
		local sentBeat: number = 0
		local sent: number = 0
		local finished: boolean = false
		local short: string? = nil

		-- One Heartbeat's turn: the batch in flight collected once every worker's round shows, then the next sent
		local function turn()
			beat += 1

			if flying then
				local count: number = Pool.landed(marks, workers, round)
				if count < workers then
					if os.clock() - sent >= BATCH_WAIT then
						short = `batch {round} had {count} of {workers} workers in after {BATCH_WAIT} s`
						finished = true
					end

					return
				end

				table.insert(batches, batchOf(marks, workers, sent, beat == sentBeat + 1))
				flying = false
			end

			if #batches >= REPEATS then
				finished = true
				return
			end

			-- Every worker is sent the batch from this one Heartbeat's serial phase
			round += 1
			sentBeat = beat
			sent = os.clock()

			for _, actor: Actor in actors do
				actor:SendMessage(Work.TOPIC, round, passes, marks)
			end

			flying = true
		end

		-- Disconnected below, once the batches are in or the wait for them ends
		connection = RunService.Heartbeat:Connect(function ()
			if finished then
				return
			end

			local turned: boolean, thrown: any = pcall(turn)
			if not turned then
				short = `a Heartbeat's turn threw: {thrown}`
				finished = true
			end
		end)

		local done: boolean = Pool.within(RUN_WAIT, function (): boolean
			return finished
		end)

		if not done then
			return `{#batches} of {REPEATS} batches were in within {RUN_WAIT} s`
		end

		return short
	end)

	local made: RBXScriptConnection? = connection
	if made then
		made:Disconnect()
	end

	return batches, stopped
end

return Pool
