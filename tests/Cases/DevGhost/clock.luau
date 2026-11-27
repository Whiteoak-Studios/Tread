--[[
    The ghosts' server clock of a render time follows the stamps the server
    sent across a u16 tick's wrap and a held tick, steps a tick's interval
    from the one stamp beside a missing one, and the ring keeps the newest
--]]

--!strict
local Client = require("../../Fixtures/DevGhost/Client")

local START: number = 1790000000 -- The server's clock at a run's first tick, seconds
local HELD: number = 0.017 -- Seconds a held tick and every tick after it are stamped late, a 60 Hz server frame
local CLOSE: number = 1e-6 -- Seconds, past the rounding of a clock near 1.79e9 and of the sums below
local MILLISECONDS: number = 1000
local WRAP: number = 2 ^ 16
local COUNT: number = 10 -- Ticks in each run of stamps
local FIRST: number = 1000 -- The first tick of the runs that stay clear of the wrap
local WRAPPING: number = WRAP - 6 -- The first tick of the run across the wrap, its seventh tick 0
local RECEIVED: number = 40 -- Ticks the module's ring is sent, past its 32
local LABEL: string = "4 relay workers"

-- A clock against the one expected, nil for none
local function off(got: number?, wanted: number?): boolean
	if got == nil or wanted == nil then
		return got ~= wanted
	end

	return math.abs(got - wanted) > CLOSE
end

--[[
    A run of COUNT ticks from first, each a relay interval after the one
    before from START, those from the held place on stamped HELD late, the
    places missing names left out. Places count from 0
--]]

local function run(first: number, interval: number, held: number?, missing: { number }?): ({ number }, { number })
	local ticks: { number } = {}
	local stamps: { number } = {}

	for place: number = 0, COUNT - 1 do
		if missing and table.find(missing, place) then
			continue
		end

		local late: number = 0
		if held ~= nil and place >= held then
			late = HELD
		end

		table.insert(ticks, (first + place) % WRAP)
		table.insert(stamps, START + place * interval + late)
	end

	return ticks, stamps
end

return function (): (boolean, string | nil)
	local rig: Client.Rig = Client.load()
	local Ghost: any = rig.Ghost
	local interval: number = 1 / rig.shared.rates.relay

	-- 1) A held tick: the clock follows the stamps on both sides of it, where a mapping at the nominal rate from the
	-- newest stamp puts a render time before it HELD late, so the lag reads HELD more than that mapping gives
	local heldTicks: { number }, heldStamps: { number } = run(FIRST, interval, 5)
	local before: number? = Ghost.serverTime(heldTicks, heldStamps, FIRST + 3.5, interval)
	local nominal: number = heldStamps[COUNT] - (COUNT - 1 - 3.5) * interval
	if off(before, START + 3.5 * interval) or not before then
		return false, `The clock 3.5 ticks into a run with tick 5 held read {before}, not {START + 3.5 * interval}`
	elseif math.abs((nominal - before) * MILLISECONDS - HELD * MILLISECONDS) > CLOSE * MILLISECONDS then
		return false, `The lag there read {(nominal - before) * MILLISECONDS} ms more than the nominal mapping's`
	end

	local cases: { { at: number, wanted: number? } } = {
		{ at = FIRST + 5, wanted = START + 5 * interval + HELD },
		{ at = FIRST + 4.5, wanted = START + 4.5 * interval + HELD / 2 },
		{ at = FIRST + 7.25, wanted = START + 7.25 * interval + HELD },
	}

	for _, case: { at: number, wanted: number? } in cases do
		local got: number? = Ghost.serverTime(heldTicks, heldStamps, case.at, interval)
		if off(got, case.wanted) then
			return false, `The clock at {case.at} in a run with tick 5 held read {got}, not {case.wanted}`
		end
	end

	-- 2) The wrap: a run from 65,530 whose seventh tick is 0, held from there, read at render times past the wrap
	-- once and twice, unwrapped as the client's render time is
	local wrapTicks: { number }, wrapStamps: { number } = run(WRAPPING, interval, 6)
	local wrapped: { { at: number, wanted: number? } } = {
		{ at = WRAP - 0.5, wanted = START + 5.5 * interval + HELD / 2 },
		{ at = WRAP + 1.25, wanted = START + 7.25 * interval + HELD },
		{ at = 2 * WRAP + 1.25, wanted = START + 7.25 * interval + HELD },
	}

	for _, case: { at: number, wanted: number? } in wrapped do
		local got: number? = Ghost.serverTime(wrapTicks, wrapStamps, case.at, interval)
		if off(got, case.wanted) then
			return false, `The clock at {case.at} across the wrap read {got}, not {case.wanted}`
		end
	end

	-- 3) A missing stamp: a tick's interval on from the one beside it that came, even where the stamp past the
	-- missing one is held, and nothing with neither
	local gapTicks: { number }, gapStamps: { number } = run(FIRST, interval, 7, { 6 })
	local gaps: { { at: number, wanted: number? } } = {
		{ at = FIRST + 5.5, wanted = START + 5.5 * interval },
		{ at = FIRST + 6.25, wanted = START + 6.25 * interval + HELD },
	}

	for _, case: { at: number, wanted: number? } in gaps do
		local got: number? = Ghost.serverTime(gapTicks, gapStamps, case.at, interval)
		if off(got, case.wanted) then
			return false, `The clock at {case.at} beside a missing tick 6 read {got}, not {case.wanted}`
		end
	end

	local wideTicks: { number }, wideStamps: { number } = run(FIRST, interval, nil, { 6, 7 })
	local neither: number? = Ghost.serverTime(wideTicks, wideStamps, FIRST + 6.5, interval)
	if neither ~= nil then
		return false, `The clock between two missing ticks read {neither}, not nothing`
	end

	-- 4) The module's ring keeps the newest 32 ticks received: tick 8, held, is gone, so a render time on it steps an
	-- interval back from tick 9, and one between ticks 7 and 8 reads nothing
	rig.start()
	rig.clock(START)
	rig.press(rig.config.key)

	for tick: number = 1, RECEIVED do
		local late: number = 0
		if tick == 8 then
			late = HELD
		end

		rig.send(tick, START + tick * interval + late, LABEL, {})
	end

	local now: number = START + (RECEIVED + 10) * interval
	rig.set.renderTime = 8
	rig.frame(now)

	local readings: any = rig.Ghost.readings()
	local lag: number = (now - (START + 9 * interval - interval)) * MILLISECONDS
	if not readings or not readings.read or math.abs(readings.lag.last - lag) > CLOSE * MILLISECONDS then
		return false, `The lag on an evicted tick read {readings and readings.lag.last} ms, not {lag}`
	elseif readings.label ~= LABEL then
		return false, `The readings are labeled {readings.label}, not {LABEL}`
	end

	rig.set.renderTime = 7.5
	rig.frame(now + rig.config.refresh)
	if readings.read or readings.lag.count ~= 1 then
		return false, `Between two evicted ticks the lag was read, {readings.lag.count} readings in all`
	end

	return true, nil
end
