--[[
    The server's tick loop: a fixed-rate accumulator on Heartbeat that runs a
    few ticks a frame at most and drops the rest, each tick's stages in order
    under a pcall each and timed, each Heartbeat's work too, waiting while held
--]]

--!strict
--!native
local RunService = game:GetService("RunService")

local Reports = require(script.Parent.Reports)

local WINDOW_SECONDS: number = 10 -- How far back each stage's times are kept, the span stats reads its p95 over
local HEARTBEATS_KEPT: number = 2400 -- Heartbeats the per-Heartbeat ring holds, so a reader once a second misses none
local LABEL_PREFIX: string = "Tread" -- Before each stage's name in its profiler label
local FINISH_LABEL: string = `{LABEL_PREFIX} finish` -- The profiler label of a hold's poll
local CALM_TICKS: number = 20 -- The calm ticks in a row a tick needs before it may defer its split stage
local CALM_GAP: number = 3 -- The fewest Heartbeats from a tick that ran alone to the next for it to count as calm

-- What a Heartbeat's entry says the loop did in it, each a bit of its flags
local TICKED: number = 1 -- A tick began in it
local HELD: number = 2 -- The tick was held as it ended
local POLLED: number = 4 -- A hold's poll was tried in it
local RELEASED: number = 8 -- A hold ended in it
local DEFERRED: number = 16 -- A deferred tick's rest ran in it

-- Lune's debug has no profiler, so the stages run unlabeled under the suite
local LABELED: boolean = debug.profilebegin ~= nil

-- What a stage runs each tick, handed the tick as the server counts it, unwrapped
export type Run = (tick: number) -> ()

-- Whether a stage given one may run on a tick, the tick as the server counts it
export type Latest = (tick: number) -> boolean

-- What a holding stage leaves to run first each Heartbeat while it holds, true once the hold may end
export type Poll = () -> boolean

-- A ring of times as a stage keeps its runs', each with the tick it ran on, which the finishes are kept in too
export type Ring = {
	times: { number }, -- A ring of seconds, a run's time each, made at its full size
	ticks: { number }, -- The tick each time's run was handed, at the time's own index in a ring of the same size
	beats: { number }, -- The Heartbeat each run came in, by the per-Heartbeat ring's count, at the same index
	held: number, -- The times the ring holds, up to its size, the first that many of times
	head: number, -- The ring index the next time goes at
	last: number, -- The newest time, 0 before the first
}

-- One stage as the loop keeps it, with its times for the last WINDOW_SECONDS
export type Stage = {
	name: string,
	run: Run,
	between: boolean, -- Whether it runs once each Heartbeat, in its first tick or alone when none is due
	latest: Latest?, -- With one, it runs only on the last of a Heartbeat's or a release's ticks this gives true for
	early: Run?, -- With one, a tick that defers runs it in the stage's place and the stage's run at the next Heartbeat
	label: string, -- Its profiler label
	times: { number }, -- A ring of seconds, a run's time each, made at its full size
	ticks: { number }, -- The tick each time's run was handed, at the time's own index in a ring of the same size
	beats: { number }, -- The Heartbeat each run came in, by the per-Heartbeat ring's count, at the same index
	held: number, -- The times the ring holds, up to its size, the first that many of times
	head: number, -- The ring index the next time goes at
	last: number, -- The newest time, 0 before the first tick
}

-- The loop's whole work each Heartbeat, by os.clock(): its stages, between stages, polls and releases, in a ring
export type Heartbeats = {
	times: { number }, -- A ring of seconds, one a Heartbeat, made at its full size
	flags: { number }, -- What the loop did in each, at the time's own index: the sum of its flags, TICKED to DEFERRED
	held: number, -- The Heartbeats the ring holds, up to its size
	head: number, -- The ring index the next Heartbeat goes at
	count: number, -- The Heartbeats since start, the one running's number while it runs
}

-- A stage as Tick.start is handed one
export type Entry = {
	name: string,
	run: Run,
	between: boolean?, -- Run once each Heartbeat: in its first tick, or with no tick due handed the newest tick run
	latest: Latest?, -- Run at most once a Heartbeat, on the last of its ticks this gives true for
	early: Run?, -- Run in its place by a tick that defers, its run and every later stage's put off to the next Heartbeat
}

-- The stages in the order each tick runs them, replaced whole when one is added so a tick running keeps its list
local Stages: { Stage } = {}
-- The between stages alone, in order, the pass a Heartbeat that owes no tick runs
local BetweenStages: { Stage } = {}

local Rate: number = 0 -- Ticks a second, the shared table's rates.simulation
local CatchUp: number = 0 -- The most ticks one Heartbeat may run, the server settings' catchUp
local Capacity: number = 0 -- Times each ring holds, WINDOW_SECONDS of ticks
local Pending: number = 0 -- The ticks owed and not yet run, a fraction of one between frames unless held
local Ran: number = 0 -- The ticks run since start, the newest one's number
local Ahead: number = 0 -- The ticks still to run after the one running, in its Heartbeat's or its release's
local Dropped: number = 0 -- The ticks dropped since start, past the catch-up of a frame or a release
local Current: string = "" -- The stage running, which a failure's warning names, empty while none runs
local Started: boolean = false
local Holding: boolean = false -- Whether a stage has held the tick and neither Tick.release nor its poll ended it
local Deferred: boolean = false -- Whether a deferred tick's rest waits for the next Heartbeat, parked as a hold's is
local Parked: { Stage }? = nil -- The stage list of the pass a hold or a deferral stopped, nil while none waits
local ParkedAt: number = 0 -- The index in that list of the first stage still to run
local ParkedFirst: boolean = false -- Whether that pass runs its between stages
local Fresh: boolean = false -- Whether a Heartbeat has come since the between stages last ran
local Polling: Poll? = nil -- The last hold's poll, nil for a hold with none, tried only while the tick is held
local Holder: string = "" -- The stage that last held the tick, which a poll that throws is reported as
local Flags: number = 0 -- What the Heartbeat running has done so far, as its entry's flags
local SplitOn: boolean = false -- Whether a calm tick may defer the stage with an early part, as Tick.useSplit set it
local Carried: number = 0 -- Seconds the waiting rest's early part took, which its stage's one entry for the tick adds
local HeldLast: boolean = false -- Whether the stage with an early part still held the tick as its last run returned
local Calm: number = 0 -- The calm ticks in a row before the newest one
local LastAlone: boolean = false -- Whether the newest tick ran alone, the one tick of a Heartbeat that ran nothing else
local LastBeat: number = 0 -- The Heartbeat the newest tick began in

-- Each poll call that ended a hold, its time and the tick held, made at its full size at start
local Finishes: Ring = { times = {}, ticks = {}, beats = {}, held = 0, head = 0, last = 0 }

-- Each Heartbeat's work, made at its full size, whose count every ring entry takes as its Heartbeat
local Beats: Heartbeats = {
	times = table.create(HEARTBEATS_KEPT, 0),
	flags = table.create(HEARTBEATS_KEPT, 0),
	held = 0,
	head = 0,
	count = 0,
}

local Tick = {
	TICKED = TICKED,
	HELD = HELD,
	POLLED = POLLED,
	RELEASED = RELEASED,
	DEFERRED = DEFERRED,
}

-- Errors from the caller of the member named when a stage's name, its after or its run is not what it takes
local function checkStage(name: string, run: Run, member: string)
	if type(name) ~= "string" or name == "" then
		error(`{member} takes a stage's name as a string, not {name}`, 3)
	elseif type(run) ~= "function" then
		error(`{member} takes the stage {name}'s run as a function, not a {typeof(run)}`, 3)
	end

	for _, stage: Stage in Stages do
		if stage.name == name then
			error(`{member} took a second stage named {name}`, 3)
		end
	end
end

local function newStage(name: string, run: Run, between: boolean, latest: Latest?, early: Run?): Stage
	return {
		name = name,
		run = run,
		between = between,
		latest = latest,
		early = early,
		label = `{LABEL_PREFIX} {name}`,
		times = table.create(Capacity, 0),
		ticks = table.create(Capacity, 0),
		beats = table.create(Capacity, 0),
		held = 0,
		head = 0,
		last = 0,
	}
end

-- Runs where a stage's error was raised, so its warning keeps the stage's stack
local function warnFailure(message: any)
	warn(`The {Current} stage threw, and its work was dropped for the tick: {debug.traceback(tostring(message), 2)}`)
end

-- The same for a stage's early part, whose loss is that part's alone, since the stage's run still follows
local function warnEarly(message: any)
	local stack: string = debug.traceback(tostring(message), 2)
	warn(`The {Current} stage's early part threw, losing the rest of that part, and its run still follows: {stack}`)
end

-- Keeps a run's time, the tick it was handed and its Heartbeat in a ring, over its oldest once the ring is full
local function record(ring: Ring, tick: number, took: number)
	-- Whiteoak TODO: a ring holds its stage's last Capacity runs, so a between stage's spans a few seconds of
	-- Heartbeats and a latest stage's more than WINDOW_SECONDS while it skips ticks; a ring sized by time would hold
	-- the whole window, once stats needs it for such a stage
	ring.times[ring.head + 1] = took
	ring.ticks[ring.head + 1] = tick
	ring.beats[ring.head + 1] = Beats.count
	ring.head = (ring.head + 1) % Capacity
	ring.held = math.min(ring.held + 1, Capacity)
	ring.last = took
end

-- One part of a stage, its run or its early part, under the stage's label and its own xpcall with the warning given,
-- giving its time and whether it ran without throwing
local function runPart(stage: Stage, run: Run, tick: number, warning: (message: any) -> ()): (number, boolean)
	Current = stage.name

	if LABELED then
		debug.profilebegin(stage.label)
	end

	local began: number = os.clock()
	local ran: boolean = xpcall(run, warning, tick)
	local took: number = os.clock() - began
	Current = ""

	if LABELED then
		debug.profileend()
	end

	return took, ran
end

--[[
    One stage's run, timed into its ring and under its own xpcall, so one
    that throws loses the rest of its own work, is reported as stage with
    its name, and stops nothing after it. A deferred tick's rest adds its
    early part's time, so the tick's one entry holds both
--]]

local function runStage(stage: Stage, tick: number)
	local took: number, ran: boolean = runPart(stage, stage.run, tick, warnFailure)

	if stage.early then
		took += Carried
		Carried = 0
	end

	record(stage, tick, took)

	if not ran then
		Reports.fire(nil, "stage", stage.name)
	end
end

-- Whether a stage runs on a tick by its latest: always with none, else when it gives true for the tick and for none
-- of the ticks still to run after it
local function runsOn(stage: Stage, tick: number): boolean
	local latest: Latest? = stage.latest
	if latest == nil then
		return true
	elseif not latest(tick) then
		return false
	end

	for later: number = tick + 1, tick + Ahead do
		if latest(later) then
			return false
		end
	end

	return true
end

--[[
    One pass over a stage list from the index from on, each stage handed
    tick, a between one run only when first is true and one with a latest
    only when runsOn finds it the last tick for it. It stops after a stage
    that holds the tick, keeping where for Tick.release, and, given splits,
    at a stage with an early part, which runs in its place while the stage
    and every one after it wait for the next Heartbeat. It says whether it
    reached the end
--]]

local function pass(stages: { Stage }, from: number, tick: number, first: boolean, splits: boolean): boolean
	for index: number = from, #stages do
		local stage: Stage = stages[index]
		if (first or not stage.between) and runsOn(stage, tick) then
			local early: Run? = stage.early
			if early and splits then
				Parked = stages
				ParkedAt = index
				Deferred = true

				local took: number, ran: boolean = runPart(stage, early, tick, warnEarly)
				Carried = took

				if not ran then
					Reports.fire(nil, "stage", stage.name)
				end

				return false
			end

			runStage(stage, tick)

			if early then
				HeldLast = Holding
			end

			if Holding then
				Parked = stages
				ParkedAt = index + 1
				ParkedFirst = first

				return false
			end
		end
	end

	return true
end

--[[
    Runs the whole ticks owed, at most the catch-up, with any further whole
    ticks dropped and counted, until a stage holds the tick and leaves the
    rest owed. Each between stage runs once a Heartbeat, in the first tick
    after one, or alone handed the newest tick run when none is owed. Given
    alone, from a Heartbeat that has run nothing else, its one tick owed may
    defer, once the split is on, the ticks before it calm and the stage with
    an early part still holding the tick as its last run returned
--]]

local function advance(alone: boolean)
	local due: number = math.floor(Pending)
	if due <= 0 then
		if Fresh then
			Fresh = false
			pass(BetweenStages, 1, Ran, true, false)
		end

		return
	end

	local running: number = math.min(due, CatchUp)
	Dropped += due - running
	Pending -= due - running

	local lone: boolean = alone and due == 1

	for index: number = 1, running do
		local first: boolean = Fresh
		Fresh = false
		Pending -= 1
		Ran += 1
		Ahead = running - index

		-- The tick before was calm when it ran alone and this one began CALM_GAP Heartbeats or more after it
		Calm = (LastAlone and Beats.count - LastBeat >= CALM_GAP) and Calm + 1 or 0
		LastAlone = lone
		LastBeat = Beats.count

		if not pass(Stages, 1, Ran, first, lone and SplitOn and HeldLast and Calm >= CALM_TICKS) then
			return
		end
	end
end

--[[
    Runs a deferred tick's rest at the Heartbeat after its own: the between
    stages first when no tick is owed, while the rest still waits so none of
    them may hold, then the deferred stage and every one after it with the
    ticks owed counted as a release counts them, so its latest skips it for
    a later tick as a catch-up does, then those ticks owed, the first with
    the between stages, none of them deferring
--]]

local function resume()
	local stages: { Stage } = Parked :: { Stage }
	local at: number = ParkedAt
	Parked = nil
	Flags = bit32.bor(Flags, DEFERRED)

	-- The ticks the advance after it runs, which the deferred stage's latest looks ahead to
	Ahead = math.min(math.floor(Pending), CatchUp)
	if Ahead == 0 then
		Fresh = false
		pass(BetweenStages, 1, Ran, true, false)
	end

	Deferred = false

	-- A rest its latest skips keeps its early part's time as the tick's one entry
	local deferred: Stage = stages[at]
	if not runsOn(deferred, Ran) then
		record(deferred, Ran, Carried)
		Carried = 0
	end

	if pass(stages, at, Ran, false, false) then
		advance(false)
	end
end

--[[
    Ends the hold: the held tick's remaining stages run, then the ticks owed
    since, or the between stages alone when a Heartbeat has come since they
    ran and none is owed, none of them deferring. Nothing parked means the
    holding stage is still running, and its pass goes on once it returns
--]]

local function release()
	Holding = false
	Flags = bit32.bor(Flags, RELEASED)

	local stages: { Stage }? = Parked
	if stages == nil then
		return
	end

	Parked = nil

	-- The ticks the advance after it runs, which the held tick's stages with a latest look ahead to
	Ahead = math.min(math.floor(Pending), CatchUp)

	if pass(stages, ParkedAt, Ran, ParkedFirst, false) then
		advance(false)
	end
end

--[[
    Tries the hold's poll, labeled and under its own xpcall. Once it answers
    true or throws, its time goes into the finishes with the tick held, a
    throw is warned and reported as stage with the holding stage's name, and
    the hold ends
--]]

local function poll(polling: Poll)
	Current = Holder

	if LABELED then
		debug.profilebegin(FINISH_LABEL)
	end

	local began: number = os.clock()
	local ran: boolean, done: boolean? = xpcall(polling, warnFailure)
	local took: number = os.clock() - began
	Current = ""

	if LABELED then
		debug.profileend()
	end

	if ran and not done then
		return
	end

	record(Finishes, Ran, took)

	if not ran then
		Reports.fire(nil, "stage", Holder)
	end

	release()
end

--[[
    Each Heartbeat adds the ticks its time owes at the rate, the fraction
    of one left over kept for the next, and runs them, unless the tick is
    held, when every stage, the between ones included, waits for the
    release, and a hold's poll is the Heartbeat's first work, or a deferred
    tick's rest waits, which is then its first work. All of it is timed
    into the per-Heartbeat ring with what it did
--]]

local function frame(delta: number)
	local began: number = os.clock()
	local before: number = Ran
	Beats.count += 1
	Flags = 0
	Pending += delta * Rate
	Fresh = true

	if Deferred then
		resume()
	elseif not Holding then
		advance(true)
	else
		local polling: Poll? = Polling
		if polling ~= nil then
			Flags = bit32.bor(Flags, POLLED)
			poll(polling)
		end
	end

	if Ran ~= before then
		Flags = bit32.bor(Flags, TICKED)
	end

	if Holding then
		Flags = bit32.bor(Flags, HELD)
	end

	local at: number = Beats.head + 1
	Beats.flags[at] = Flags
	Beats.head = at % HEARTBEATS_KEPT
	Beats.held = math.min(Beats.held + 1, HEARTBEATS_KEPT)
	Beats.times[at] = os.clock() - began
end

--[[
    Starts the loop at rate ticks a second on Heartbeat with the stages in
    the order given, running at most catchUp ticks a frame, each stage
    marked between once every Heartbeat, with a tick due or not, each
    given a latest on the last of a Heartbeat's or a release's ticks it
    gives true for, and at most one stage, never a between one, given an
    early part that a calm tick runs in its place while the split is on.
    The Heartbeat connection lives as long as the server, which never stops
    its tick
--]]

function Tick.start(rate: number, catchUp: number, stages: { Entry })
	if Started then
		error("Tick.start runs once, and it has already run", 2)
	elseif type(rate) ~= "number" or not (rate > 0 and rate < math.huge) then
		error(`Tick.start takes the rate as ticks a second above 0, not {rate}`, 2)
	elseif type(catchUp) ~= "number" or catchUp < 1 or catchUp % 1 ~= 0 then
		error(`Tick.start takes the catch-up as a whole number of ticks from 1, not {catchUp}`, 2)
	elseif type(stages) ~= "table" then
		error(`Tick.start takes its stages as a list, not a {typeof(stages)}`, 2)
	end

	Rate = rate
	CatchUp = catchUp
	Capacity = math.ceil(WINDOW_SECONDS * rate)
	Finishes.times = table.create(Capacity, 0)
	Finishes.ticks = table.create(Capacity, 0)
	Finishes.beats = table.create(Capacity, 0)

	local split: boolean = false -- Whether a stage before has an early part

	for _, entry: Entry in stages do
		checkStage(entry.name, entry.run, "Tick.start")

		local between: boolean? = entry.between
		if between ~= nil and type(between) ~= "boolean" then
			error(`Tick.start takes the stage {entry.name}'s between as true, false or nil, not {between}`, 2)
		end

		local latest: Latest? = entry.latest
		if latest ~= nil and type(latest) ~= "function" then
			error(`Tick.start takes the stage {entry.name}'s latest as a function or nil, not a {typeof(latest)}`, 2)
		end

		local early: Run? = entry.early
		if early ~= nil and type(early) ~= "function" then
			error(`Tick.start takes the stage {entry.name}'s early as a function or nil, not a {typeof(early)}`, 2)
		elseif early ~= nil and split then
			error(`Tick.start takes an early part on one stage at most, and {entry.name} is a second`, 2)
		elseif early ~= nil and between == true then
			error(`Tick.start takes no early part on a between stage, as {entry.name} is`, 2)
		end

		split = split or early ~= nil

		local stage: Stage = newStage(entry.name, entry.run, between == true, latest, early)
		table.insert(Stages, stage)

		if stage.between then
			table.insert(BetweenStages, stage)
		end
	end

	Started = true

	-- Lives as long as the server
	RunService.Heartbeat:Connect(frame)
end

--[[
    Adds a stage to every tick from the next, directly after the stage
    named after, so it runs before whatever ran after that one. A name
    taken, or an after naming no stage, is refused
--]]

function Tick.addStage(name: string, after: string, stageRun: Run)
	if not Started then
		error("Tick.addStage ran before Tick.start", 2)
	end

	checkStage(name, stageRun, "server:addStage")

	local at: number? = nil
	local names: { string } = {}

	for index: number, stage: Stage in Stages do
		table.insert(names, stage.name)

		if stage.name == after then
			at = index
		end
	end

	if at == nil then
		local known: string = table.concat(names, ", ")
		error(`server:addStage takes the name of a stage to run after, and {after} is none of {known}`, 2)
	end

	-- A copy, so a tick running now finishes on the list it started with
	local stages: { Stage } = table.clone(Stages)
	table.insert(stages, at + 1, newStage(name, stageRun, false))
	Stages = stages
end

--[[
    Holds the tick from inside a running stage: once that stage returns,
    the rest of its tick and every later tick wait for Tick.release, while
    each Heartbeat still adds the time it owes. Given a poll, each Heartbeat
    while held runs it first and ends the hold once it answers true or
    throws, a throw reported as the holding stage's, so the poll itself
    never calls Tick.release. A hold outside a stage, one while a deferred
    tick's rest waits, from an early part or a between stage run before
    the rest, a second one before the release, and a poll that is no
    function are refused
--]]

function Tick.hold(polling: Poll?)
	if Current == "" then
		error("Tick.hold runs only inside a running stage", 2)
	elseif Deferred then
		error(`Tick.hold came from the {Current} stage while a deferred tick's rest waits, so it may not hold`, 2)
	elseif Holding then
		error(`Tick.hold came again from the {Current} stage while the tick is already held`, 2)
	elseif polling ~= nil and type(polling) ~= "function" then
		error(`Tick.hold takes its poll as a function or nil, not a {typeof(polling)}`, 2)
	end

	Holding = true
	Polling = polling
	Holder = Current
end

--[[
    Ends a hold: the held tick's remaining stages run, then the ticks owed
    since, at most the catch-up in all, with any further whole ticks
    dropped and counted, or the between stages alone when a Heartbeat has
    come since they ran and no tick is owed. A release before the holding
    stage returns lets its tick go straight on, and one with nothing held
    is refused
--]]

function Tick.release()
	if not Holding then
		error("Tick.release found no hold to release", 2)
	end

	release()
end

--[[
    The ticks run since start, which is the newest tick's number, and the
    ticks dropped since start past the catch-up of each frame or release
--]]

function Tick.counts(): (number, number)
	return Ran, Dropped
end

--[[
    The stages in the order each tick runs them, with their times and the
    tick each ran on, for stats to read. The list is the loop's own, which a
    reader leaves as it is
--]]

function Tick.stages(): { Stage }
	return Stages
end

--[[
    Each hold's poll call that ended it, its time and the tick it held, in a
    ring of its own beside the stages', which a reader leaves as it is
--]]

function Tick.finishes(): Ring
	return Finishes
end

--[[
    The loop's whole work each Heartbeat, its time by os.clock() and what it
    did, in a ring of its own whose count numbers the Heartbeats every other
    ring's entries carry, which a reader leaves as it is
--]]

function Tick.heartbeats(): Heartbeats
	return Beats
end

-- Whether a stage has held the tick and nothing has released it yet, or a deferred tick's rest waits for the next
-- Heartbeat, so the newest tick's work is not all done
function Tick.holding(): boolean
	return Holding or Deferred
end

--[[
    Sets whether a calm tick may defer from the next tick: the stage with an
    early part runs that part in its place, and its run with every stage
    after it waits for the next Heartbeat. Off, no early part runs and each
    tick runs whole, while a rest already waiting still runs at the next
    Heartbeat. It is off from start
--]]

function Tick.useSplit(on: boolean)
	if type(on) ~= "boolean" then
		error(`Tick.useSplit takes true or false, not {on}`, 2)
	end

	SplitOn = on
end

-- Whether a calm tick may defer, as Tick.useSplit last set it
function Tick.splitOn(): boolean
	return SplitOn
end

return Tick
