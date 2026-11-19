--[[
    A worker's failure raised in the finish is reported as the relay stage's
    after the flush and the frame, and the tick released; a stage that
    throws after holding waits for its finish; inside the timeout none ends
--]]

--!strict
local Lockstep = require("../../Fixtures/Server/Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 60 -- Seconds, far past every Heartbeat here
local FAILING: number = 1 -- The worker whose result is a failure
local FAIL_AT: number = 3 -- The tick whose round lands with that failure
local THROW_AT: number = 5 -- The tick whose stage throws after holding, its round delivered
local WAIT_AT: number = 7 -- The tick whose round is held back for WAITS Heartbeats of a tick each
local WAITS: number = 3
local TICKS: number = 10
local FAILURE: string = "A planted failure out of worker 1's Remote.run"
local PLANTED: string = "A planted failure after the relay's dispatch"

type Side = Lockstep.Side

return function (): (boolean, string | nil)
	local side: Side = Lockstep.side({ workers = WORKERS, timeout = TIMEOUT })
	local pool: any = side.pool
	local Tick: any = side.Tick

	-- Worker 1's round of the failing tick lands as a failure
	local landed: any = pool.landed
	local failing: number? = nil
	pool.landed = function (self: any, worker: number, round: number): (buffer?, string?)
		local result: buffer?, failure: string? = landed(self, worker, round)
		if worker == FAILING and round == failing and (result ~= nil or failure ~= nil) then
			return nil, FAILURE
		end

		return result, failure
	end

	local relay: any = side.Characters.relay
	side.Characters.relay = function (relayTick: number, tick: number)
		relay(relayTick, tick)
		if relayTick == THROW_AT then
			error(PLANTED)
		end
	end

	local slices: any = nil
	for _, stage: any in Tick.stages() do
		if stage.name == "antiEsp" then
			slices = stage
		end
	end

	local reportedAt: { [number]: number } = {} -- The stage reports heard by the end of each beat

	for beat: number = 1, TICKS do
		if beat == FAIL_AT then
			-- The round this tick dispatches is the relay's FAIL_AT-th
			failing = FAIL_AT
		end

		Lockstep.beat(side, 1)
		reportedAt[beat] = #side.rig:reported("stage")

		if beat == WAIT_AT then
			-- Inside the timeout a round never landed holds every Heartbeat, slices and all
			local ran: number = Tick.counts()
			local sliced: number = slices.held
			local framed: number = #side.frames.Client

			for _ = 1, WAITS do
				Lockstep.beat(side, 1)
			end

			if Tick.counts() ~= ran or slices.held ~= sliced or #side.frames.Client ~= framed then
				return false, `Held for {WAITS} Heartbeats, the tick ran on to {Tick.counts()} from {ran}`
			elseif side.server:stats().relayDropped ~= 0 then
				return false, "A round inside the timeout was given up"
			end
		end

		side.pool:deliver()
	end

	Lockstep.beat(side, 1)

	-- The failure in the finish: reported at the beat after its tick, which still framed that tick and ran on
	local reported: { number | string } = side.rig:reported("stage")
	if reportedAt[FAIL_AT] ~= 0 or reportedAt[FAIL_AT + 1] ~= 1 or reported[1] ~= "relay" then
		return false, `The finish's failure was reported {reportedAt[FAIL_AT + 1]} times by tick {FAIL_AT + 1}`
	end

	local failed: string? = side.frames.Client[FAIL_AT]
	if failed == nil then
		return false, "The failing tick had no frame"
	end

	local frame: any = side.Tap.read(buffer.fromstring(failed))
	if frame.tick ~= FAIL_AT or frame.owner == nil then
		return false, `The failing tick's frame was tick {frame.tick}'s, its OwnerState {frame.owner}`
	end

	-- The stage's throw reported at its own beat, the hold kept until the finish at the next framed its tick
	local thrown: string? = side.frames.Client[THROW_AT]
	if reportedAt[THROW_AT] ~= 2 or reported[2] ~= "relay" or thrown == nil then
		return false, `The stage that threw after holding was reported {reportedAt[THROW_AT] - 1} times`
	elseif side.Tap.read(buffer.fromstring(thrown)).tick ~= THROW_AT then
		return false, `The frame after the stage that threw was not its tick {THROW_AT}'s`
	end

	-- The held Heartbeats' ticks at the release: the catch-up's two after the held tick's rest, the rest dropped,
	-- the relay on the second alone, so tick 8 holds nothing and the last beat's dispatch is still out
	local read: any = side.server:stats()
	local finishes: any = Tick.finishes()
	local ticks: { string } = {}
	for index: number = 1, finishes.held do
		table.insert(ticks, `{finishes.ticks[index]}`)
	end

	local expected: string = "1,2,3,4,5,6,7,9,10,11"
	if table.concat(ticks, ",") ~= expected or read.dropped ~= WAITS - 1 or read.relaySkipped ~= 1 then
		local counts: string = `{read.dropped} dropped and {read.relaySkipped} relay ticks skipped`
		return false, `The finishes held ticks {table.concat(ticks, ",")}, with {counts}`
	elseif #reported ~= 2 or read.relayDropped ~= 0 then
		return false, `The run gave {#reported} stage reports and {read.relayDropped} rounds dropped`
	end

	return true, nil
end
