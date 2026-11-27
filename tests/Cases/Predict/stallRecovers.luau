--[[
    A server stall past the catch-up drops ticks and puts the client's
    commands past the ahead limit: after a short stall and the live run's
    long one alike, the server runs every command again within the bound
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local WARM: number = 15 -- Seconds of normal delivery the clock settles in first
local SHORT: number = 0.2 -- A stall dropping 2 ticks, which leaves the commands inside the queue's reach
local LONG: number = 0.5 -- The live run's planned stall, dropping 8, which puts every copy past the limit
local CHECK: number = 5 -- Seconds checked once the bound has passed

return function (): (boolean, string | nil)
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	local tick: number = 1 / rig.shared.rates.simulation
	rig.run(WARM)

	for _, seconds: number in { SHORT, LONG } do
		rig.take()
		rig.stallServer(seconds)

		-- Through the stall and the Heartbeat that ends it, which runs its catch-up and drops the rest
		rig.run(seconds + tick)
		local dropped: number = rig.take().dropped
		if dropped == 0 then
			return false, `A {seconds} s stall dropped no tick, so it tested nothing`
		end

		-- Each dropped tick puts the client's numbers one further past the server's, which the clock holds back by
		local bound: number = dropped + ticks.ahead + ticks.resync
		rig.run(bound * tick)

		local settled: boolean, reason: string? = rig.settled(CHECK)
		if not settled then
			return false, `{bound} ticks after a {seconds} s stall that dropped {dropped}, {reason}`
		end
	end

	return true, nil
end
