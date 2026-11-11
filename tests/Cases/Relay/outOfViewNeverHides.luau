--[[
    The out-of-view rate sets only how often a player behind the viewer is
    sent, never whether: it is revealed on the first run, never hidden, and
    stays sent and drawn on every run after
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40
local RATE: number = 5 -- Hz, the out-of-view rate the case sets
local CONE: number = 60
local RADIUS: number = 15
local STRIDE: number = 0.1
local AHEAD: vector = vector.create(0, 0, -1)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.outOfView = { rate = RATE, cone = CONE, radius = RADIUS }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = AHEAD

	-- One near and one far, both behind the viewer and past the radius
	local targets: { number } = {
		harness:spawn("Player", vector.create(0, 0, 100)),
		harness:spawn("Player", vector.create(0, 0, 500)),
	}

	for run: number = 1, RUNS do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in targets do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		for _, slot: number in targets do
			if run == 1 and Harness.find(client.seen.reveals, slot) == nil then
				return false, `The player behind in slot {slot} was not revealed on the first run`
			elseif Harness.count(client.seen.hides, slot) > 0 then
				return false, `The player behind in slot {slot} was hidden on run {run}`
			elseif not Harness.Relay.isSent(client.viewer.key, slot) or client.drawn[slot] == nil then
				return false, `The player behind in slot {slot} was not sent and drawn after run {run}`
			end
		end
	end

	return true, nil
end
