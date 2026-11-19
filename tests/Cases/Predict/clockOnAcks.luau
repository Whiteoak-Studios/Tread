--[[
    A client sent acknowledgments a Heartbeat later than the OwnerStates
    they stand in for, with a full one a second and a Heartbeat earlier,
    holds its lead in band with no snap and no search, and its trip reads
    at most a command longer than OwnerStates alone give
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

-- Seconds each way, at frame phases that put the Heartbeat an acknowledgment waits either side of a client tick
local DELAYS: { number } = { 0.05, 0.08, 0.15, 0.17 }
local WARM: number = 15 -- Seconds the clock finds its lead in first
local CHECK: number = 20 -- Seconds checked once it has
local FULL_EVERY: number = 20 -- Ticks between full OwnerStates though the check agreed, a second at 20 Hz
local LONGER: number = 1 -- The most commands a Heartbeat's wait can add to a trip

type Window = Link.Window

-- The checked window of a link whose acknowledgments are on or off, and why it failed, or nil
local function run(oneWay: number, acks: boolean): (Window, string?)
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	rig.up = oneWay
	rig.down = oneWay
	rig.acks = acks
	rig.ackDelay = rig.serverFrame
	rig.fullEvery = acks and FULL_EVERY or nil

	rig.run(WARM)
	rig.take()
	rig.run(CHECK)

	local window: Window = rig.take()
	local ahead: number = window.reports.ahead or 0
	local late: number = window.reports.late or 0
	if window.standIns > 0 or ahead > 0 or late > 0 then
		return window, `the server ran {window.standIns} stand-ins, with {ahead} ahead and {late} late reports`
	elseif window.corrections > 0 then
		return window, `the client raised {window.corrections} corrections`
	elseif acks and (window.acks == 0 or window.acks == window.ticks) then
		return window, `{window.acks} of the {window.ticks} ticks went as acknowledgments`
	end

	for depth: number, count: number in window.depths do
		if depth < ticks.leadMin or depth > ticks.leadMax then
			return window, `{count} of what the server sent carried a queue of {depth}, outside the band`
		end
	end

	-- A snap skips numbers or holds them back, and a search does one or the other
	if window.moves ~= #window.numbers or window.samples ~= window.moves then
		return window, `{window.moves} Moves went, {#window.numbers} with commands, from {window.samples} samples`
	end

	for index: number = 2, #window.numbers do
		local step: number = rig.Sequence.difference(window.numbers[index], window.numbers[index - 1])
		if step ~= 1 then
			return window, `the client's newest command moved by {step} from one Move to the next`
		end
	end

	return window, nil
end

-- The least and the most of a list of trips
local function span(trips: { number }): (number, number)
	local least: number, most: number = math.huge, -math.huge

	for _, trip: number in trips do
		least = math.min(least, trip)
		most = math.max(most, trip)
	end

	return least, most
end

return function (): (boolean, string | nil)
	local lengthened: boolean = false

	for _, oneWay: number in DELAYS do
		local plain: Window, plainFailure: string? = run(oneWay, false)
		if plainFailure then
			return false, `With OwnerStates alone at {oneWay} s each way, {plainFailure}`
		end

		local acked: Window, ackedFailure: string? = run(oneWay, true)
		if ackedFailure then
			return false, `With acknowledgments at {oneWay} s each way, {ackedFailure}`
		end

		local least: number, most: number = span(plain.trips)
		local ackedLeast: number, ackedMost: number = span(acked.trips)
		if #acked.trips == 0 or ackedLeast < least or ackedMost > most + LONGER then
			local trips: string = `{ackedLeast} to {ackedMost} commands against {least} to {most}`
			return false, `At {oneWay} s each way the trips acknowledgments gave read {trips}`
		end

		lengthened = lengthened or ackedMost > most
	end

	-- Some phase must put a client tick inside the wait, or the acknowledgments were never late
	if not lengthened then
		return false, "At no delay did a trip read longer, so no acknowledgment waited out a client tick"
	end

	return true, nil
end
