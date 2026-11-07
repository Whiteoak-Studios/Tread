--[[
    Load like the live run's, a server stall each second of up to 0.25 s,
    drops ticks in bursts, and once delivery is normal again the server
    runs every one of the client's commands within the bound
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local WARM: number = 15 -- Seconds of normal delivery the clock settles in first
local CHECK: number = 5 -- Seconds checked once the bound has passed

-- Each second of load, the moment its stall starts and how long it lasts, in seconds
local LOAD: { { number } } = {
	{ 0.3, 0.12 },
	{ 0.1, 0.2 },
	{ 0.5, 0.08 },
	{ 0.2, 0.25 },
	{ 0.4, 0.15 },
	{ 0, 0.22 },
	{ 0.3, 0.1 },
	{ 0.6, 0.25 },
	{ 0.2, 0.18 },
	{ 0.5, 0.06 },
	{ 0.1, 0.24 },
	{ 0.4, 0.14 },
	{ 0.3, 0.2 },
	{ 0.6, 0.1 },
	{ 0.2, 0.25 },
}

return function (): (boolean, string | nil)
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	local tick: number = 1 / rig.shared.rates.simulation
	rig.run(WARM)
	rig.take()

	for _, second: { number } in LOAD do
		local at: number, stall: number = second[1], second[2]
		rig.run(at)
		rig.stallServer(stall)
		rig.run(1 - at)
	end

	local load: any = rig.take()
	if load.dropped == 0 or (load.reports.ahead or 0) == 0 then
		return false, `The load dropped {load.dropped} ticks and raised no ahead report, so it tested nothing`
	end

	-- The last stall drops at most a few ticks, which the clock holds back by as for one stall
	local bound: number = ticks.ahead + ticks.resync
	rig.run(bound * tick)

	local settled: boolean, reason: string? = rig.settled(CHECK)
	if not settled then
		return false, `{bound} ticks after load that dropped {load.dropped} ticks in bursts, {reason}`
	end

	return true, nil
end
