--[[
    A respawn at 150 ms each way ends the body, and the next OwnerState starts
    the next one the way the first started, its numbers run on past the last
    body's: none is sent twice, and the server runs every command again
--]]

--!strict
local Link = require("../../Fixtures/Predict/Link")

local ONE_WAY: number = 0.15 -- Seconds each way
local WARM: number = 20 -- Seconds the first body plays, its clock settled long before the end
local SLACK: number = 1 -- The tick a round may lose to both sides' frames
local FRAME: number = 1 / 60 -- Seconds a step takes while the next OwnerState is awaited
local WAIT: number = 2 -- Seconds the next OwnerState may take to reach the client
local CHECK: number = 5 -- Seconds checked once the bound has passed

return function (): (boolean, string | nil)
	local rig: any = Link.new()
	local ticks: any = rig.shared.ticks
	local rate: number = rig.shared.rates.simulation
	rig.up = ONE_WAY
	rig.down = ONE_WAY
	rig.run(WARM)

	local before: number? = rig.newest
	if before == nil then
		return false, "The first body sent no command"
	end

	-- The server's body keeps stepping as a new character's does, and the Moves already in flight still reach it
	rig.Predict.reset()
	rig.take()

	local waited: number = 0
	while rig.Predict.state() == nil do
		if waited >= WAIT then
			return false, `No OwnerState started the next body in {WAIT} s`
		end

		rig.run(FRAME)
		waited += FRAME
	end

	-- Its first command sits at the last body's lead, so the server reaches it a trip and the band's top later
	local limit: number = 2 * ONE_WAY * rate + ticks.leadMax + SLACK
	rig.run(limit / rate)

	local window: any = rig.take()
	local first: number? = window.numbers[1]
	if first == nil then
		return false, "The next body sent no command"
	elseif rig.Sequence.difference(first, before) <= 0 then
		return false, `The next body's first Move carried command {first}, sent before by the last body up to {before}`
	end

	local tampered: number = window.reports.moveTamper or 0
	if tampered > 0 then
		return false, `The respawn raised {tampered} moveTamper reports`
	end

	local settled: boolean, reason: string? = rig.settled(CHECK)
	if not settled then
		return false, `{limit} ticks after the next body started, {reason}`
	end

	return true, nil
end
