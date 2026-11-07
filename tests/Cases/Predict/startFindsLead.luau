--[[
    A client's first body finds its lead by the search, never the nudge: at
    50, 150 and 250 ms each way and on a jittered link, the server runs every
    command, its queue in band, within the bound the search's rounds give
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local DELAYS: { number } = { 0.05, 0.15, 0.25 } -- Seconds each way
local JITTERED: number = 0.15 -- Seconds each way the jittered link keeps on average
local SPREAD: number = 0.04 -- The most seconds the jittered uplink is off its average

-- Seconds the jittered uplink is off its average, one a tick in turn, the downlink off by half as much the other way
local JITTER: { number } = { 0.03, -0.02, 0.04, -0.04, 0.01, 0, -0.03, 0.02, -0.01, 0.04, -0.02, 0.03 }

local SLACK: number = 1 -- The tick a round may lose to both sides' frames
local FRAME: number = 1 / 60 -- Seconds a step takes while the first OwnerState is awaited
local WAIT: number = 2 -- Seconds the first OwnerState may take to reach the client
local CHECK: number = 5 -- Seconds checked once the bound has passed

--[[
    The ticks a start may take at a round trip of the ticks given: a tick
    before the first judgment, then a late round for each step the trip
    holds and one more, the j-th lasting its j steps and a tick, and the
    skip up to the target after it as long as the last. Each limit from
    ticks.ahead, doubling, that the search's floor passes adds its own climb
    and the hold back from it
--]]

local function bound(trip: number, ticks: any): number
	local step: number = math.max(math.round((ticks.leadMin + ticks.leadMax) / 2), 1)

	local function climb(to: number): number
		local rounds: number = to // step + 1

		return SLACK + step * rounds * (rounds + 1) / 2 + rounds * SLACK + rounds * step + SLACK
	end

	local total: number = climb(trip)
	local limit: number = ticks.ahead
	while limit + SLACK < trip do
		total += climb(limit) + limit
		limit *= 2
	end

	return total
end

-- Runs the link until the client reads its first OwnerState, and opens a window from there
local function started(rig: any): (boolean, string | nil)
	local waited: number = 0
	while rig.Predict.state() == nil do
		if waited >= WAIT then
			return false, `No OwnerState reached the client in {WAIT} s`
		end

		rig.run(FRAME)
		waited += FRAME
	end

	rig.take()

	return true, nil
end

return function (): (boolean, string | nil)
	for _, oneWay: number in DELAYS do
		local rig: any = Link.new()
		local ticks: any = rig.shared.ticks
		local rate: number = rig.shared.rates.simulation
		rig.up = oneWay
		rig.down = oneWay

		local began: boolean, failure: string? = started(rig)
		if not began then
			return false, failure
		end

		local limit: number = bound(2 * oneWay * rate + SLACK, ticks)
		rig.run(limit / rate)

		local settled: boolean, reason: string? = rig.settled(CHECK)
		if not settled then
			return false, `{limit} ticks after the first OwnerState at {oneWay} s each way, {reason}`
		end
	end

	-- The jittered link, its delays set again before every tick
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	local rate: number = rig.shared.rates.simulation
	local turn: number = 0

	local function run(count: number)
		for _ = 1, count do
			local off: number = JITTER[turn % #JITTER + 1]
			turn += 1
			rig.up = JITTERED + off
			rig.down = JITTERED - off / 2
			rig.run(1 / rate)
		end
	end

	rig.up = JITTERED
	rig.down = JITTERED

	local began: boolean, failure: string? = started(rig)
	if not began then
		return false, failure
	end

	local limit: number = bound(2 * (JITTERED + SPREAD) * rate + SLACK, ticks)
	run(math.ceil(limit))
	rig.take()
	run(CHECK * rate)

	local window: any = rig.take()
	local ahead: number = window.reports.ahead or 0
	local late: number = window.reports.late or 0
	if window.standIns > 0 or ahead > 0 or late > 0 then
		local reports: string = `{window.standIns} stand-ins, {ahead} ahead and {late} late reports`
		return false, `{limit} ticks after the first OwnerState on the jittered link, the server ran {reports}`
	end

	for depth: number, count: number in window.depths do
		if depth < ticks.leadMin or depth > ticks.leadMax then
			return false, `On the jittered link {count} OwnerStates carried a queue of {depth}`
		end
	end

	return true, nil
end
