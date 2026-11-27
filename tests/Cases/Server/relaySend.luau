--[[
    stats gives relaySend, the smoothed seconds from a tick's decode to the
    flush that sent its blocks, on a stand-in clock: a Heartbeat on the
    workers, two once the split defers, none in process; the history's send
    lag takes it while the split is on with workers, else is 0
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local RATE: number = 20 -- The example's relay rate, Hz
local SMOOTHING: number = 1 -- The example's rewind.rttSmoothing, seconds
local ON: number = SplitSide.CALM + 4 -- The ticks run with the split on from start
local OFF: number = 3 -- The ticks run after it goes off, before it comes on again
local AGAIN: number = 3 -- And after that
local TOLERANCE: number = 1e-12 -- Seconds two sums of the same exact steps may part by
local TIMEOUT: number = 60 -- Seconds no measure on the real clock reaches, the fixture's round timeout

type Driven = SplitSide.Driven

-- The send's time after one more measure, smoothed as the server smooths it over one relay tick
local function smoothed(send: number?, measure: number): number
	if send == nil then
		return measure
	end

	local weight: number = 1 - math.exp(-1 / RATE / SMOOTHING)

	return send + weight * (measure - send)
end

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true, clock = true })
	local side: any = driven.side
	local History: any = side.rig:require(side.rig.tread.Server.History)

	local send: number? = nil
	local before: number = 0 -- The send's time as the tick's decode found it, which the history's term takes
	local on: boolean = true
	local deferring: number = SplitSide.CALM -- The first tick each stretch with the split on defers

	for tick: number = 1, ON + OFF + AGAIN do
		if tick == ON + 1 then
			side.Tick.useSplit(false)
			on = false
		elseif tick == ON + OFF + 1 then
			side.Tick.useSplit(true)
			on = true

			-- The calm count goes on while the split is off, so the first tick after it comes on defers
			deferring = tick
		end

		before = send or 0
		SplitSide.ticks(driven, 1)

		-- A deferred tick's blocks go two Heartbeats after its decode, the finish's flush, and any other's one after
		local deferred: boolean = on and tick >= deferring
		send = smoothed(send, (deferred and 2 or 1) * SplitSide.STEP)

		local read: number = side.server:stats().relaySend
		local term: number = History.sendLagSeconds()
		local fed: number = on and before or 0

		if math.abs(read - (send :: number)) > TOLERANCE then
			return false, `After tick {tick} stats gave relaySend {read}, not {send}`
		elseif math.abs(term - fed) > TOLERANCE then
			return false, `After tick {tick}, with the split on {on}, the history's send lag was {term}, not {fed}`
		end
	end

	-- In process every block leaves in its tick's own flush, on the tick's own Heartbeat
	local inProcess: Driven = SplitSide.new({ split = true, workers = false, clock = true })
	SplitSide.ticks(inProcess, OFF)

	local read: number = inProcess.side.server:stats().relaySend
	if read ~= 0 then
		return false, `In process stats gave relaySend {read} on the stand-in clock, not 0`
	end

	-- On the real clock the measure is above 0, and with no round out to defer the history's term stays 0, split on
	local real: Driven = SplitSide.new({ split = true, workers = false })
	SplitSide.ticks(real, OFF)

	local measured: number = real.side.server:stats().relaySend
	local lag: number = real.side.rig:require(real.side.rig.tread.Server.History).sendLagSeconds()
	if not (measured > 0 and measured < TIMEOUT) or lag ~= 0 then
		return false, `In process on the real clock stats gave relaySend {measured} and a send lag of {lag}`
	end

	return true, nil
end
