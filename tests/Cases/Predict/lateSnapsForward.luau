--[[
    A client whose frame freezes past its time debt really is late, its
    queue empty with a trip that still holds: it snaps forward past the
    ticks it lost, as the design gives, and its commands run again
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local ONE_WAY: number = 0.15 -- Seconds each way, so the client's newest number stays ahead of the server's tick
local WARM: number = 30 -- Seconds the clock takes to settle its start at that round trip
local LOST: number = 5 -- Ticks the freeze costs past the time debt
local CHECK: number = 5 -- Seconds checked once the bound has passed

return function (): (boolean, string | nil)
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	local rate: number = rig.shared.rates.simulation
	local half: number = 0.5 -- Of a tick, so the freeze owes its ticks whatever the rounding
	rig.up = ONE_WAY
	rig.down = ONE_WAY
	rig.run(WARM)

	local before: number? = rig.newest
	if before == nil then
		return false, "The client sent no command before the freeze"
	end

	local freeze: number = (LOST + ticks.debt + half) / rate
	rig.take()
	rig.stallClient(freeze)
	rig.run(freeze + 1 / rate)

	local after: any = rig.take()
	local first: number? = after.numbers[1]
	if first == nil then
		return false, "The client sent no command after the freeze"
	end

	-- The first command after it is numbered past the next by the numbers skipped
	local skipped: number = rig.Sequence.difference(first, before) - 1
	if skipped < LOST then
		return false, `After a freeze that lost {LOST} ticks the clock skipped {skipped} numbers`
	end

	local trip: number = 2 * ONE_WAY * rate
	local bound: number = trip + ticks.ahead + ticks.resync
	rig.run(bound / rate)

	local settled: boolean, reason: string? = rig.settled(CHECK)
	if not settled then
		return false, `{bound} ticks after a freeze that lost {LOST} ticks, {reason}`
	end

	return true, nil
end
