--[[
    The parallel probes on the client: while a Workspace attribute names a
    window, P6 counts the worker threads this client runs and when their work
    lands, or P8 times a leg bend on workers against the main thread
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local Network = require(ReplicatedStorage.Shared.Network.Client)

local Cost = require(script.Parent.Parent.Cost)
local InterpretedLoop = require(script.Parent.Parent.InterpretedLoop)
local Lines = require(script.Parent.Lines)
local ParallelConfig = require(script.Parent.Parent.Config).parallel
local Rig = require(script.Parent.Parent.Rig)
local Work = require(script.Parent.Work)

-- The Actor every worker is cloned from, which never works itself, and beside which its clones are parented
local Template = script.Parent.Worker

local CORES_ATTRIBUTE: string = ParallelConfig.attributes.cores
local BEND_ATTRIBUTE: string = ParallelConfig.attributes.bend
local READY_WAIT: number = ParallelConfig.readyWait
local RESULT_WAIT: number = ParallelConfig.resultWait
local WORKERS: { number } = ParallelConfig.cores.workers
local REPEATS: number = ParallelConfig.cores.repeats
local WORK_MS: number = ParallelConfig.cores.workMs
local BYTES: number = ParallelConfig.cores.bytes
local TRIAL_PASSES: number = ParallelConfig.cores.trialPasses
local TRIALS: number = ParallelConfig.cores.trials
local BATCH_WAIT: number = ParallelConfig.cores.batchWait
local RUN_WAIT: number = ParallelConfig.cores.runWait
local LANDING_EVENTS: { string } = ParallelConfig.landing.events
local LANDING_WORKERS: number = ParallelConfig.landing.workers
local HOLD_MS: number = ParallelConfig.landing.holdMs
local LANDING_FRAMES: number = ParallelConfig.landing.frames
local LANDING_SECONDS: number = ParallelConfig.landing.seconds
local BEND_WORKERS: { number } = ParallelConfig.bend.workers
local BEND_STEPS: number = ParallelConfig.bend.steps
local BEND_SECONDS: number = ParallelConfig.bend.seconds
local SETTLE: number = ParallelConfig.bend.settle
local AT: Vector3 = ParallelConfig.bend.at
local RISE: Work.Rise = ParallelConfig.bend.rise
local MILLISECONDS: number = 1000
local STEPPED: string = Work.STEPPED
local HOME: string = "ParallelStandIns" -- The Workspace folder an arm's stand-ins stand in

local SIGNALS: { [string]: RBXScriptSignal<number> } = Work.signals()

-- How a P8 arm bends its stand-ins: not at all, on the main thread, or on workers
type Mode = "off" | "serial" | "workers"

-- What a probe measures in its window, giving its clauses so far and what stopped it, nil when nothing did
type Measure = (live: () -> boolean) -> ({ string }, string?)

local Running: boolean = false
local Probing: string? = nil -- The window a probe measures, nil between windows

local Probe = {}

--[[
    Waits a Heartbeat at a time until the check passes, giving nil once it
    does, or what stopped the wait: the window closing, or the wait's own
    deadline passing, each naming what it waited for
--]]

local function within(what: string, seconds: number, live: () -> boolean, check: () -> boolean): string?
	local by: number = os.clock() + seconds

	while not check() do
		if not live() then
			return `the window closed while {what}`
		elseif os.clock() >= by then
			return `{what} took past its {seconds} s`
		end

		RunService.Heartbeat:Wait()
	end

	return nil
end

--[[
    Waits a Heartbeat at a time until that many of the counted event have
    fired since it began or its seconds pass, which both end an arm, and
    gives how many fired, or nil once the window closed
--]]

local function counted(
	counters: SharedTable,
	event: string,
	most: number,
	seconds: number,
	live: () -> boolean
): number?
	local first: number = counters[event]
	local by: number = os.clock() + seconds

	while counters[event] - first < most and os.clock() < by do
		if not live() then
			return nil
		end

		RunService.Heartbeat:Wait()
	end

	return counters[event] - first
end

-- How many of the workers have that attribute set
local function marked(actors: { Actor }, attribute: string): number
	local count: number = 0
	for _, actor: Actor in actors do
		if actor:GetAttribute(attribute) == true then
			count += 1
		end
	end

	return count
end

--[[
    Clones that many workers beside the template, waits for each to bind its
    topics, then runs the body with them. It gives why it stopped short, the
    body's own reason or a throw, nil when it didn't, and destroys every
    clone whatever happened, which ends its script and its callbacks
--]]

local function pooled(workers: number, live: () -> boolean, body: ({ Actor }) -> string?): string?
	local actors: { Actor } = {}

	local ran: boolean, result: any = pcall(function (): string?
		for index: number = 1, workers do
			local actor: Actor = Template:Clone()
			actor.Name = `Worker{index}`
			actor:SetAttribute(Work.WORKER, index)
			table.insert(actors, actor)

			-- Parented once its index is set, so its script finds it as it starts
			actor.Parent = script.Parent
		end

		-- A message sent before a worker binds its topics is never taken, so none goes until every one has
		local waited: string? = within(
			`waiting for {Lines.named(workers)} to bind`,
			READY_WAIT,
			live,
			function (): boolean
				return marked(actors, Work.BOUND) == workers
			end
		)

		if waited then
			return `{waited}, and {marked(actors, Work.BOUND)} of {workers} did`
		end

		return body(actors)
	end)

	for _, actor: Actor in actors do
		actor:Destroy()
	end

	if not ran then
		return `it threw: {result}`
	end

	return result
end

--[[
    Ends the workers' arm: each is sent the results table and hands in its
    samples, which this waits for until its own deadline. It gives each
    worker's samples, empty for one that never did, and why it stopped
    short, nil when it didn't
--]]

local function collect(actors: { Actor }, live: () -> boolean): ({ { number } }, string?)
	local results: SharedTable = SharedTable.new()
	for _, actor: Actor in actors do
		actor:SendMessage(Work.STOP, results)
	end

	local waited: string? = within(
		`waiting for the samples of {Lines.named(#actors)}`,
		RESULT_WAIT,
		live,
		function (): boolean
			for index: number = 1, #actors do
				if results[index] == nil then
					return false
				end
			end

			return true
		end
	)

	local samples: { { number } } = {}
	for index: number = 1, #actors do
		local stored: SharedTable? = results[index]
		local list: { number } = {}

		if stored then
			for at: number = 1, SharedTable.size(stored) do
				list[at] = stored[at]
			end
		end

		samples[index] = list
	end

	return samples, waited
end

-- Counts each frame event into the counters from a serial handler of its own, giving what disconnects them all
local function countEvents(counters: SharedTable): () -> ()
	local connections: { RBXScriptConnection } = {}
	for _, name: string in Work.EVENTS do
		counters[name] = 0
		table.insert(
			connections,
			SIGNALS[name]:Connect(function ()
				counters[name] += 1
			end)
		)
	end

	return function ()
		for _, connection: RBXScriptConnection in connections do
			connection:Disconnect()
		end
	end
end

--[[
    Sizes the loop to about WORK_MS on this client, from the fastest of
    TRIALS timed runs of TRIAL_PASSES passes, then times it REPEATS times
    run serially on the main thread. It gives the passes and each run's
    seconds, and errors when the sizing runs took no time to measure
--]]

local function serial(): (number, { number })
	local data: buffer = buffer.create(BYTES)
	local fastest: number = math.huge

	for _ = 1, TRIALS do
		local began: number = os.clock()
		InterpretedLoop(data, TRIAL_PASSES)
		fastest = math.min(fastest, os.clock() - began)
	end

	if not (fastest > 0 and fastest < math.huge) then
		error(`{TRIALS} sizing runs of {TRIAL_PASSES} passes gave no time to size the loop by`, 0)
	end

	local passes: number = math.max(1, math.round(TRIAL_PASSES * WORK_MS / MILLISECONDS / fastest))
	local times: { number } = table.create(REPEATS, 0)

	for run: number = 1, REPEATS do
		local began: number = os.clock()
		InterpretedLoop(data, passes)
		times[run] = os.clock() - began
	end

	return passes, times
end

-- How many of the first that many workers' marks show the round
local function landed(marks: SharedTable, workers: number, round: number): number
	local landedCount: number = 0
	for worker: number = 1, workers do
		if marks[(worker - 1) * Work.FIELDS + Work.ROUND] == round then
			landedCount += 1
		end
	end

	return landedCount
end

-- The batch in the marks, sent at that os.clock(), and whether it was in at the Heartbeat after the send
local function batchOf(marks: SharedTable, workers: number, sent: number, byNext: boolean): Lines.Batch
	local starts: { number } = table.create(workers, 0)
	local finishes: { number } = table.create(workers, 0)

	for worker: number = 1, workers do
		local base: number = (worker - 1) * Work.FIELDS
		starts[worker] = marks[base + Work.START]
		finishes[worker] = marks[base + Work.FINISH]
	end

	return { sent = sent, starts = starts, finishes = finishes, byNext = byNext }
end

--[[
    From one Heartbeat connection, sends that many workers the batch at one
    Heartbeat and collects it at a later one, until REPEATS batches are in.
    It gives the batches in and why it stopped short, nil when it didn't,
    and takes away the connection and every clone whatever happened
--]]

local function batches(workers: number, passes: number, live: () -> boolean): ({ Lines.Batch }, string?)
	local landedBatches: { Lines.Batch } = {}
	local connection: RBXScriptConnection? = nil

	local stopped: string? = pooled(workers, live, function (actors: { Actor }): string?
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
				local count: number = landed(marks, workers, round)
				if count < workers then
					if os.clock() - sent >= BATCH_WAIT then
						short = `batch {round} had {count} of {workers} workers in after {BATCH_WAIT} s`
						finished = true
					end

					return
				end

				table.insert(landedBatches, batchOf(marks, workers, sent, beat == sentBeat + 1))
				flying = false
			end

			if #landedBatches >= REPEATS then
				finished = true
				return
			end

			-- Every worker is sent the batch from this one Heartbeat's serial phase
			round += 1
			sentBeat = beat
			sent = os.clock()

			for _, actor: Actor in actors do
				actor:SendMessage(Work.CORES, round, passes, BYTES, marks)
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

		local what: string = `sending {REPEATS} batches to {Lines.named(workers)}`
		local waited: string? = within(what, RUN_WAIT, live, function (): boolean
			return finished
		end)

		if waited then
			return `{waited}, with {#landedBatches} in`
		end

		return short
	end)

	local made: RBXScriptConnection? = connection
	if made then
		made:Disconnect()
	end

	return landedBatches, stopped
end

--[[
    One landing arm on the workers: each one's callbacks on the event hold
    their thread, read every frame event's count and read them again once
    synchronized, until that many of the event fire or its seconds pass. It
    gives each worker's samples, the events counted, and why it stopped
    short, nil when it didn't
--]]

local function land(actors: { Actor }, event: string, live: () -> boolean): ({ { number } }, number, string?)
	local counters: SharedTable = SharedTable.new()
	local stopCounting: () -> () = countEvents(counters)

	local ran: boolean, samples: any, events: any, short: any = pcall(function (): ({ { number } }, number, string?)
		for _, actor: Actor in actors do
			actor:SendMessage(Work.LAND, event, HOLD_MS / MILLISECONDS, counters)
		end

		local fired: number? = counted(counters, event, LANDING_FRAMES, LANDING_SECONDS, live)
		local collected: { { number } }, failure: string? = collect(actors, live)
		if fired == nil then
			return collected, 0, `the window closed during the {event} arm`
		end

		return collected, fired, failure
	end)

	-- The counting goes whatever the arm did
	stopCounting()

	if not ran then
		return {}, 0, `it threw: {samples}`
	end

	return samples, events, short
end

-- P6: the loop timed serially, each worker count's batches, then each landing arm on one pool of workers
local function cores(live: () -> boolean): ({ string }, string?)
	local passes: number, times: { number } = serial()
	local counts: { Lines.Measured } = {}

	for _, workers: number in WORKERS do
		local got: { Lines.Batch }, stopped: string? = batches(workers, passes, live)
		table.insert(counts, Lines.measure(workers, REPEATS, got))

		if stopped then
			return { Lines.counts(times, passes, counts) }, `{Lines.named(workers)} stopped short: {stopped}`
		end
	end

	local clauses: { string } = { Lines.counts(times, passes, counts) }
	local stopped: string? = pooled(LANDING_WORKERS, live, function (actors: { Actor }): string?
		for _, event: string in LANDING_EVENTS do
			local samples: { { number } }, events: number, short: string? = land(actors, event, live)
			if short then
				return `the {event} arm stopped short: {short}`
			end

			table.insert(clauses, Lines.landing(event, samples, events))
		end

		return nil
	end)

	return clauses, stopped
end

--[[
    Readies a clone of the rig template as a stand-in: no Humanoid, script,
    socket, no-collision pair or Animator, so its joints keep whatever is
    written to them, nothing that collides, is queried or is touched, and
    its root alone anchored, as Tread's pool readies its own clone
--]]

local function strip(rig: Model)
	local root: BasePart? = rig.PrimaryPart

	for _, item: Instance in rig:GetDescendants() do
		if
			item:IsA("Humanoid")
			or item:IsA("BaseScript")
			or item:IsA("BallSocketConstraint")
			or item:IsA("NoCollisionConstraint")
			or item:IsA("AnimationController")
			or item:IsA("Animator")
		then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = item == root
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
end

-- Fills the folder with that many stand-ins, every one where the stand-ins stand, and gives them
local function standIns(folder: Folder, count: number): { Model }
	local prepared: Model = Rig.template():Clone()
	strip(prepared)
	prepared:PivotTo(CFrame.new(AT))

	local rigs: { Model } = {}
	for _ = 1, count do
		local rig: Model = prepared:Clone()
		rig.Parent = folder
		table.insert(rigs, rig)
	end

	prepared:Destroy()

	return rigs
end

-- The rigs cut into that many slices end to end, the first ones a rig longer when they don't divide
local function slices(rigs: { Model }, count: number): { { Model } }
	local cut: { { Model } } = {}
	local from: number = 1

	for index: number = 1, count do
		local length: number = #rigs // count
		if index <= #rigs % count then
			length += 1
		end

		local slice: { Model } = {}
		table.move(rigs, from, from + length - 1, 1, slice)
		table.insert(cut, slice)
		from += length
	end

	return cut
end

-- The main thread's own callback in the serial arm, kept in a worker's sample layout, its resume its solve's end
local function record(samples: { number }, step: number, start: number, solved: number, written: number, before: number)
	local layout = Work.BENDING
	local at: number = #samples

	samples[at + layout.STEP] = step
	samples[at + layout.START] = start
	samples[at + layout.SOLVED] = solved
	samples[at + layout.SYNCED] = solved
	samples[at + layout.WRITTEN] = written
	samples[at + layout.BEFORE] = before
	samples[at + layout.AFTER] = before
end

--[[
    One of P8's arms over stand-ins of its own: off, serial with the main
    thread solving and writing every leg in its PreSimulation handler, or
    on that many workers, a slice each. After the settle, it stamps each
    step's PreSimulation and PostSimulation and reads each slice's first
    foot at PreRender, until its steps or seconds run out. Every connection,
    worker and stand-in it made goes whatever happened
--]]

local function arm(rigCount: number, mode: Mode, workers: number, live: () -> boolean): (Lines.Arm?, string?)
	local folder: Folder = Instance.new("Folder")
	folder.Name = HOME

	local connections: { RBXScriptConnection } = {}
	local counters: SharedTable = SharedTable.new()
	counters[STEPPED] = 0

	local ran: boolean, made: any, failure: any = pcall(function (): (Lines.Arm?, string?)
		local rigs: { Model } = standIns(folder, rigCount)
		folder.Parent = Workspace

		local cut: { { Model } } = {}
		if mode == "serial" then
			cut = { rigs }
		elseif mode == "workers" then
			cut = slices(rigs, math.min(workers, rigCount))
		end

		-- Each slice's set on the main thread, whose first foot is read, and which the serial arm also bends
		local reads: { Work.Set } = {}
		for _, slice: { Model } in cut do
			table.insert(reads, Work.set(slice, Rig.joints))
		end

		local pres: { [number]: number } = {}
		local posts: { [number]: number } = {}
		local lags: { number } = {}
		local own: { number } = {}
		local recording: boolean = false
		local from: number = 0 -- The steps counted as the window began, after which a foot read shows one of its bends

		table.insert(
			connections,
			SIGNALS.PostSimulation:Connect(function ()
				local step: number = counters[STEPPED] + 1
				counters[STEPPED] = step

				if recording then
					posts[step] = os.clock()
				end
			end)
		)

		table.insert(
			connections,
			SIGNALS.PreSimulation:Connect(function ()
				local start: number = os.clock()
				local before: number = counters[STEPPED]
				local step: number = before + 1

				if recording then
					pres[step] = start
				end

				if mode ~= "serial" then
					return
				end

				local set: Work.Set = reads[1]
				Work.solve(set, Work.height(RISE, step))
				local solved: number = os.clock()

				Work.write(set)
				local written: number = os.clock()

				if recording then
					record(own, step, start, solved, written, before)
				end
			end)
		)

		if mode ~= "off" then
			table.insert(
				connections,
				SIGNALS.PreRender:Connect(function ()
					local latest: number = counters[STEPPED]
					if not recording or latest <= from then
						return
					end

					for _, set: Work.Set in reads do
						table.insert(lags, Lines.lag(Work.lifted(set), latest, RISE))
					end
				end)
			)
		end

		-- The settle, then the steps counted, then the samples, the workers' handed in at the arm's end
		local function measure(actors: { Actor }?): (Lines.Arm?, string?)
			if counted(counters, STEPPED, math.huge, SETTLE, live) == nil then
				return nil, "the window closed while the stand-ins settled"
			end

			from = counters[STEPPED]
			recording = true
			local steps: number? = counted(counters, STEPPED, BEND_STEPS, BEND_SECONDS, live)
			recording = false

			local samples: { { number } } = {}
			if mode == "serial" then
				samples = { own }
			end

			local short: string? = nil
			if actors then
				samples, short = collect(actors, live)
			end

			if steps == nil then
				return nil, "the window closed while its steps were counted"
			elseif short then
				return nil, short
			end

			-- The serial arm's one set of samples is the main thread's own, which its clause names apart
			local named: number = 0
			if mode == "workers" then
				named = #cut
			end

			return Lines.arm(named, pres, posts, samples, lags), nil
		end

		if mode ~= "workers" then
			return measure(nil)
		end

		local result: Lines.Arm? = nil
		local stopped: string? = pooled(#cut, live, function (actors: { Actor }): string?
			for index: number, actor: Actor in actors do
				actor:SendMessage(Work.BEND, cut[index], Rig.joints, counters, RISE)
			end

			local waited: string? = within(
				`waiting for {Lines.named(#cut)} to arm`,
				READY_WAIT,
				live,
				function (): boolean
					return marked(actors, Work.ARMED) == #actors
				end
			)

			if waited then
				return `{waited}, and {marked(actors, Work.ARMED)} of {#actors} did`
			end

			local measured: Lines.Arm?, short: string? = measure(actors)
			result = measured

			return short
		end)

		return result, stopped
	end)

	-- Everything the arm made goes, whatever it did
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	folder:Destroy()

	if not ran then
		return nil, `it threw: {made}`
	end

	return made, failure
end

-- P8: as many stand-ins as remote rigs are drawn, the off arm, the serial arm, then each worker count's arm
local function bend(live: () -> boolean): ({ string }, string?)
	local rigCount: number = Cost.drawn()
	if rigCount < 1 then
		return {}, "no remote rig was drawn as the window opened, so P8 had none to stand in for"
	end

	local off: Lines.Arm?, offFailure: string? = arm(rigCount, "off", 0, live)
	if not off then
		return {}, `the off arm stopped short: {offFailure}`
	end

	local arms: { Lines.Arm } = {}
	local serialArm: Lines.Arm?, serialFailure: string? = arm(rigCount, "serial", 0, live)
	if not serialArm then
		return { Lines.bend(rigCount, off, arms) }, `the serial arm stopped short: {serialFailure}`
	end

	table.insert(arms, serialArm)

	for _, workers: number in BEND_WORKERS do
		local made: Lines.Arm?, failure: string? = arm(rigCount, "workers", workers, live)
		if not made then
			return { Lines.bend(rigCount, off, arms) }, `the {Lines.named(workers)} arm stopped short: {failure}`
		end

		table.insert(arms, made)
	end

	return { Lines.bend(rigCount, off, arms) }, nil
end

--[[
    Runs a probe in the window of that label, its every wait stopping once
    the attribute no longer names it, and sends its line, unmeasured with
    what stopped it when something did
--]]

local function report(attribute: string, label: string, probe: Measure)
	local function live(): boolean
		return Workspace:GetAttribute(attribute) == label
	end

	local ran: boolean, clauses: any, failure: any = pcall(probe, live)
	if not ran then
		clauses, failure = {}, `it threw: {clauses}`
	end

	Network.clientCost.fire(label, failure == nil, Lines.line(Player.Name, clauses, failure))
end

-- The attribute changed: a label it now holds runs its probe, unless another probe still measures
local function changed(attribute: string, probe: Measure)
	local label: any = Workspace:GetAttribute(attribute)
	if type(label) ~= "string" or Probing then
		return
	end

	Probing = label

	task.spawn(function ()
		local sent: boolean, failure: any = pcall(report, attribute, label, probe)
		Probing = nil

		if not sent then
			warn(`The parallel probe of {label} sent no line: {failure}`)
		end
	end)
end

--[[
    Starts the probes once a client. Its two listeners live for the client
    session, and each window's workers, stand-ins and connections go when
    its probe ends
--]]

function Probe.start()
	if Running then
		error("Probe.start runs once a client, and it has already run", 2)
	end

	Running = true

	Workspace:GetAttributeChangedSignal(CORES_ATTRIBUTE):Connect(function ()
		changed(CORES_ATTRIBUTE, cores)
	end)

	Workspace:GetAttributeChangedSignal(BEND_ATTRIBUTE):Connect(function ()
		changed(BEND_ATTRIBUTE, bend)
	end)
end

return Probe
