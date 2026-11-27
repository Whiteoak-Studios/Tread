--[[
    A player held to the out-of-view rate behind the viewer is sent a record
    on the very run the viewer's look turns to face it, a run before its
    own tier rate would have sent one
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RATE: number = 5 -- Hz, the out-of-view rate the case sets
local CONE: number = 60
local RADIUS: number = 15
local STRIDE: number = 0.1
local AHEAD: vector = vector.create(0, 0, -1)
local BEHIND: vector = vector.create(0, 0, 1)

-- At 5 Hz of a 20 Hz relay the target's records go on runs 1, 5, 9, 13 and 17, none between. On run 18 its far aim of
-- 15 Hz alone would bring its credit only from 0 to 0.75, short of a record, so only the promotion sends one then
local LAST_LOWERED: number = 17
local INTERVAL: number = 4 -- Runs between its records at the out-of-view rate
local TURN: number = 18

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.outOfView = { rate = RATE, cone = CONE, radius = RADIUS }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = AHEAD

	-- In the far tier behind the viewer
	local target: number = harness:spawn("Player", vector.create(0, 0, 500))

	for run: number = 1, TURN do
		if run == TURN then
			client.viewer.look = BEHIND
		end

		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		harness.states[target].position += vector.create(step, 0, 0)
		harness:run()

		local sent: number = Harness.count(client.seen.records, target)
		if run == LAST_LOWERED and sent ~= 1 then
			return false, `The target behind got no record on run {run}, so the case's runs are out of phase`
		elseif run > LAST_LOWERED - INTERVAL and run < LAST_LOWERED and sent ~= 0 then
			return false, `The target behind got a record on run {run}, off its out-of-view rate`
		elseif run == TURN and sent ~= 1 then
			return false, `The target behind got {sent} records on the run the look turned to it, not 1`
		end
	end

	return true, nil
end
