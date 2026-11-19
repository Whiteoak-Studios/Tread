--[[
    One of the relay's Actor workers, run in a clone of its Actor: loads
    Remote in the serial phase, runs each round's turns desynchronized and
    fires the round's result or failure back by its Actor's BindableEvent
--]]

--!strict
local Layout = require(script.Parent.Layout)

type Run = (shared: buffer, own: buffer) -> (buffer, buffer?)

-- The template sits in the game's packages with no index, so only a clone the pool parents ever works
local found: Actor? = script:GetActor()
if not found then
	return
end

local index: unknown = found:GetAttribute(Layout.WORKER)
if type(index) ~= "number" then
	return
end

-- The pool parents each clone's event before the clone, so a worker without one was never the pool's
local made = found:FindFirstChildOfClass("BindableEvent") :: BindableEvent?
if not made then
	return
end

local actor: Actor = found
local worker: number = index
local event: BindableEvent = made

local Run: Run? = nil -- Remote.run, nil until the setup has loaded Remote and run Remote.setup
local FireFailed: boolean = false -- Whether a desynchronized fire has failed, which is warned of once
local Fired: number = 0 -- With relay.clocks on, the seconds the last round's fire took, which the next fire carries

-- The Actor owns both bindings, and the pool destroying it releases them
actor:BindToMessage(Layout.SETUP, function (remote: ModuleScript, settings: unknown)
	-- require can't run desynchronized, so Remote is loaded here in the serial phase
	local loaded: boolean, Remote: any = pcall(require, remote)
	if not loaded then
		return warn(`Relay worker {worker} could not require Remote, so it stays unready: {Remote}`)
	end

	local setUp: boolean, failure: any = pcall(Remote.setup, settings)
	if not setUp then
		return warn(`Relay worker {worker} could not run Remote.setup, so it stays unready: {failure}`)
	end

	Run = Remote.run
	actor:SetAttribute(Layout.READY, true)
end)

actor:BindToMessageParallel(Layout.RUN, function (round: number, shared: buffer, own: buffer)
	local start: number = os.clock()
	local run: Run? = Run
	local result: buffer? = nil
	local failure: string? = nil
	local clocks: buffer? = nil

	-- A throw out of Remote.run means a bad hand-in or a broken worker, since Remote catches each viewer's own
	if run then
		local ran: boolean, value: any, timed: any = pcall(run, shared, own)
		if ran then
			result = value
			clocks = timed
		else
			failure = `{value}`
		end
	else
		failure = `Relay worker {worker} was sent round {round} before its setup`
	end

	local finish: number = os.clock()

	-- With clocks, the round before's fire goes with this one, and this one's is timed from the run's finish
	local lastFire: number? = nil
	if clocks then
		lastFire = Fired
	end

	-- Whiteoak TODO: the event is the only return path; if G0's numbers pick the SharedTable, this fire becomes each
	-- worker writing its result into its own keys of one shared table, as anti-ESP's Actor arm does
	local fired: boolean, thrown: any =
		pcall(event.Fire, event, round, result, failure, start, finish, clocks, lastFire)
	if fired then
		if clocks then
			Fired = os.clock() - finish
		end

		return
	end

	-- Fired again in the serial phase, so the round still lands, with the error kept on the Actor
	task.synchronize()

	if not FireFailed then
		FireFailed = true
		actor:SetAttribute(Layout.FIRE_FAILED, `{thrown}`)

		local failed: string = `Relay worker {worker} could not fire its BindableEvent desynchronized`
		warn(`{failed}, so it fires in the serial phase: {thrown}`)
	end

	event:Fire(round, result, failure, start, finish, clocks, lastFire)

	if clocks then
		Fired = os.clock() - finish
	end
end)

actor:SetAttribute(Layout.BOUND, true)
