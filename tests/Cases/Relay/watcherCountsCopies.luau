--[[
    A watcher counts only for the blocks copied to it: an entry that rode a
    block before a second moderator joined clears once the target and the
    first moderator acknowledge that block, though the newcomer never does
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local NEAR: vector = vector.create(30, 0, 0)
local AWAY: vector = vector.create(1500, 0, 0) -- Past the target's relevancy
local NEVER: number = 1000 -- More blocks than the case sends, so the newcomer reads none

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local first: any = harness:viewer("First")
	local late: any = harness:viewer("Late")
	first.viewer.position = AWAY
	late.viewer.position = AWAY

	local slot: number = harness:spawn("Player", NEAR)
	harness:watch(first, target)
	harness:runs(2)

	-- The hide rides a block to the target and the first moderator, whose acknowledgment arrives a run late
	first.lag = 1
	harness.states[slot].position = AWAY + AWAY
	harness:run()

	if Harness.count(first.seen.hides, slot) ~= 1 then
		return false, "The first moderator was not copied the hide"
	end

	-- The newcomer joins and reads nothing; the hide rides on to all three until that first block is acknowledged
	harness:watch(late, target)
	late.lose = NEVER
	harness:run()

	if Harness.count(target.seen.hides, slot) ~= 1 or late.seen.lost == 0 then
		return false, "The hide did not ride the newcomer's first copy while the first moderator's word was late"
	end

	harness:run()
	if Harness.count(target.seen.hides, slot) ~= 0 then
		return false, "The newcomer was required for a block that was never copied to it"
	end

	return true, nil
end
