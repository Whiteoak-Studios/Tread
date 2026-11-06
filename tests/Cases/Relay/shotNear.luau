--[[
    A shooter whose bullet passed near the viewer is sent to it at no less
    than shotNear.rate for shotNear.seconds, past the soft budget too, and
    then falls back to its floor
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TICKS: number = 20 -- A second at the example's 20 Hz relay
local RATE: number = 20 -- A shot's rate, raised for this case over the example's 10 Hz
local SECONDS: number = 1
local FAR_FLOOR: number = 10
local SLACK: number = 1
local SOFT: number = 64 * 1000

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.shotNear.rate = RATE
		server.shotNear.seconds = SECONDS
	end)

	local client: any = harness:viewer("Viewer")
	local shooter: number = harness:spawn("Player", vector.create(500, 0, 0))
	local bystander: number = harness:spawn("Player", vector.create(-500, 0, 0))
	harness:run()

	local function second(slots: { number }): { [number]: number }
		local counts: { [number]: number } = {}

		for _ = 1, TICKS do
			for _, slot: number in slots do
				harness.states[slot].position += vector.create(0.1, 0, 0)
			end

			harness:run()

			for _, slot: number in slots do
				counts[slot] = (counts[slot] or 0) + Harness.count(client.seen.records, slot)
			end
		end

		return counts
	end

	-- Past the soft budget, a shot near the viewer lifts its shooter to the shot's rate and the other keeps its floor
	harness.traffic = SOFT + 1
	Harness.Relay.shotNear(client.viewer.key, shooter)

	local counts: { [number]: number } = second({ shooter, bystander })
	if counts[shooter] ~= RATE then
		return false, `The shooter was sent {counts[shooter]} records the second after its shot, not {RATE}`
	elseif math.abs(counts[bystander] - FAR_FLOOR) > SLACK then
		return false, `The bystander was sent {counts[bystander]} records, not its far floor of {FAR_FLOOR}`
	end

	counts = second({ shooter, bystander })
	if math.abs(counts[shooter] - FAR_FLOOR) > SLACK then
		return false, `Past shotNear.seconds the shooter was sent {counts[shooter]} records, not its floor`
	end

	return true, nil
end
