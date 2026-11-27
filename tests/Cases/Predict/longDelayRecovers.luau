--[[
    A long delay both ways ends, all at once or the downlink first, and the
    round trip the clock last measured is then wrong: it finds its lead again
    and the server runs every command within the bound, the queue in band
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local WARM: number = 15 -- Seconds of normal delivery the clock settles in first
local EXTRA: number = 1 -- Seconds the delay adds each way
local LASTING: number = 10 -- Seconds it lasts
local GAP: number = 2 -- Seconds the uplink stays delayed after the downlink clears, in the staged ending
local CHECK: number = 5 -- Seconds checked once the bound has passed

return function (): (boolean, string | nil)
	for _, staged: boolean in { false, true } do
		local rig: any = Link.new()
		local ticks: any = rig.shared.ticks
		local rate: number = rig.shared.rates.simulation
		local up: number, down: number = rig.up, rig.down
		rig.run(WARM)

		rig.up = up + EXTRA
		rig.down = down + EXTRA
		rig.run(LASTING)

		if staged then
			rig.down = down
			rig.run(GAP)
		end

		rig.up = up
		rig.down = down

		-- The uplink's delay clearing puts the client's numbers that many ticks further past the server's, which
		-- the clock holds back by, waiting out the numbers already sent once for a stale trip and once for its search;
		-- a queue left full is then nudged back into the band, a tick in every 1 / nudge
		local extra: number = EXTRA * rate
		local nudged: number = (ticks.ahead - 1 - ticks.leadMax) / ticks.nudge
		local bound: number = 2 * extra + ticks.ahead + ticks.resync + nudged
		rig.run(bound / rate)

		local settled: boolean, reason: string? = rig.settled(CHECK)
		if not settled then
			local ending: string = staged and `the downlink first, {GAP} s before the uplink` or "both at once"
			return false, `{bound} ticks after a {EXTRA} s delay each way ended {ending}, {reason}`
		end
	end

	return true, nil
end
