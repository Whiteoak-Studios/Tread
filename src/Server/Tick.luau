--[[
    The server's tick loop: a fixed-rate accumulator on Heartbeat that runs a
    few ticks a frame at most and drops the rest, each tick's stages in order,
    each under a pcall of its own and timed for stats
--]]

--!strict
--!native
local RunService = game:GetService("RunService")

local Reports = require(script.Parent.Reports)

local WINDOW_SECONDS: number = 10 -- How far back each stage's times are kept, the span stats reads its p95 over
local LABEL_PREFIX: string = "Tread" -- Before each stage's name in its profiler label

-- Lune's debug has no profiler, so the stages run unlabeled under the suite
local LABELED: boolean = debug.profilebegin ~= nil

-- What a stage runs each tick, handed the tick as the server counts it, unwrapped
export type Run = (tick: number) -> ()

-- One stage as the loop keeps it, with its times for the last WINDOW_SECONDS
export type Stage = {
	name: string,
	run: Run,
	label: string, -- Its profiler label
	times: { number }, -- A ring of seconds, a tick's time each, made at its full size
	held: number, -- The times the ring holds, up to its size, the first that many of times
	head: number, -- The ring index the next time goes at
	last: number, -- The newest time, 0 before the first tick
}

-- A stage as Tick.start is handed one
export type Entry = {
	name: string,
	run: Run,
}

-- The stages in the order each tick runs them, replaced whole when one is added so a tick running keeps its list
local Stages: { Stage } = {}

local Rate: number = 0 -- Ticks a second, the shared table's rates.simulation
local CatchUp: number = 0 -- The most ticks one Heartbeat may run, the server settings' catchUp
local Capacity: number = 0 -- Times each ring holds, WINDOW_SECONDS of ticks
local Pending: number = 0 -- The ticks owed and not yet run, a fraction of one between frames
local Ran: number = 0 -- The ticks run since start, the newest one's number
local Dropped: number = 0 -- The ticks dropped since start, past the catch-up a frame
local Current: string = "" -- The stage running, which a failure's warning names
local Started: boolean = false

local Tick = {}

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

local function newStage(name: string, run: Run): Stage
	return {
		name = name,
		run = run,
		label = `{LABEL_PREFIX} {name}`,
		times = table.create(Capacity, 0),
		held = 0,
		head = 0,
		last = 0,
	}
end

-- Runs where a stage's error was raised, so its warning keeps the stage's stack
local function warnFailure(message: any)
	warn(`The {Current} stage threw, and its work was dropped for the tick: {debug.traceback(tostring(message), 2)}`)
end

--[[
    One tick: every stage in order, each timed and under its own xpcall, so
    one that throws loses the rest of its own work for the tick, is
    reported as stage with its name, and stops no later stage
--]]

local function run(tick: number)
	local stages: { Stage } = Stages

	for index: number = 1, #stages do
		local stage: Stage = stages[index]
		Current = stage.name

		if LABELED then
			debug.profilebegin(stage.label)
		end

		local began: number = os.clock()
		local ran: boolean = xpcall(stage.run, warnFailure, tick)
		local took: number = os.clock() - began

		if LABELED then
			debug.profileend()
		end

		stage.times[stage.head + 1] = took
		stage.head = (stage.head + 1) % Capacity
		stage.held = math.min(stage.held + 1, Capacity)
		stage.last = took

		if not ran then
			Reports.fire(nil, "stage", stage.name)
		end
	end
end

--[[
    Each Heartbeat: the ticks its time owes at the rate, at most the
    catch-up, with any further whole ticks dropped and counted and the
    fraction of a tick left over kept for the next frame
--]]

local function frame(delta: number)
	Pending += delta * Rate

	local due: number = math.floor(Pending)
	if due <= 0 then
		return
	end

	Pending -= due

	local running: number = math.min(due, CatchUp)
	Dropped += due - running

	for _ = 1, running do
		Ran += 1
		run(Ran)
	end
end

--[[
    Starts the loop at rate ticks a second on Heartbeat with the stages in
    the order given, running at most catchUp ticks a frame. The Heartbeat
    connection lives as long as the server, which never stops its tick
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

	for _, entry: Entry in stages do
		checkStage(entry.name, entry.run, "Tick.start")
		table.insert(Stages, newStage(entry.name, entry.run))
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
	table.insert(stages, at + 1, newStage(name, stageRun))
	Stages = stages
end

--[[
    The ticks run since start, which is the newest tick's number, and the
    ticks dropped since start past each frame's catch-up
--]]

function Tick.counts(): (number, number)
	return Ran, Dropped
end

--[[
    The stages in the order each tick runs them, with their times, for
    stats to read. The list is the loop's own, which a reader leaves as it is
--]]

function Tick.stages(): { Stage }
	return Stages
end

return Tick
