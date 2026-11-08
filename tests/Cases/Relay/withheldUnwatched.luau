--[[
    A target nobody watches gets no withheld block for its culled players,
    nor does one whose last watcher has stopped, and its blocks go to it
    alone again
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local CULLED: vector = vector.create(20, 0, 0)
local VISIBLE: vector = vector.create(0, 0, 20)
local STRIDE: vector = vector.create(0, 0, 0.5)
local TICKS: number = 4

-- Why a run sent a withheld block or a block to more than the target, or nil when it sent neither
local function alone(harness: any, target: any): string?
	if #harness.withheldSends ~= 0 then
		return "A target nobody watches had a withheld block sent"
	end

	for _, keys: { any } in harness.sends do
		if #keys ~= 1 and table.find(keys, target.viewer.key) then
			return "A block of a target nobody watches went to more than the target"
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local culled: number = harness:spawn("Player", CULLED)
	local visible: number = harness:spawn("Player", VISIBLE)
	harness:hide(target, culled, true)

	for _ = 1, TICKS do
		harness.states[visible].position += STRIDE
		harness:run()

		local reason: string? = alone(harness, target)
		if reason then
			return false, reason
		end
	end

	harness:watch(moderator, target)
	harness:run()
	if #harness.withheldSends == 0 then
		return false, "A watched target's culled player was not withheld to its watcher"
	end

	harness:watch(moderator, nil)
	for _ = 1, TICKS do
		harness.states[visible].position += STRIDE
		harness:run()

		local reason: string? = alone(harness, target)
		if reason then
			return false, `Once its last watcher stopped: {reason}`
		end
	end

	return true, nil
end
