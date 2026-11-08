--[[
    A watcher that stops watching, or leaves, stops being required: the
    entries a moderator that reads nothing holds back ride every block only
    while it watches, and clear on the next run once it stops or is gone
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local NEAR: vector = vector.create(30, 0, 0)
local AWAY: vector = vector.create(1500, 0, 0) -- Past the target's relevancy
local NEVER: number = 1000 -- More blocks than the case sends, so a moderator reads none
local HELD: number = 3 -- Runs the deaf moderator holds an entry back for
local FIRST: { [string]: any } = { head = 5 }
local SECOND: { [string]: any } = { head = 6 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local stopping: any = harness:viewer("Stopping")
	local leaving: any = harness:viewer("Leaving")
	stopping.viewer.position = AWAY
	leaving.viewer.position = AWAY

	local slot: number = harness:spawn("Player", NEAR)
	harness:run()

	-- Each moderator in turn reads nothing, so the look entry rides every block while it watches
	for _, moderator: any in { stopping, leaving } do
		harness:watch(moderator, target)
		harness:run()

		moderator.lose = NEVER
		if moderator == stopping then
			Harness.Relay.setLook(slot, FIRST)
		else
			Harness.Relay.setLook(slot, SECOND)
		end

		for run: number = 1, HELD do
			harness:run()
			if Harness.count(target.seen.looks, slot) ~= 1 then
				return false, `Run {run} left out the look entry {moderator.viewer.key.Name} had not acknowledged`
			end
		end

		if moderator == stopping then
			harness:watch(stopping, nil)
		else
			local index: number? = table.find(harness.viewers, leaving.viewer)
			if index then
				table.remove(harness.viewers, index)
			end

			Harness.Relay.remove(leaving.viewer.key)
		end

		harness:run()
		if Harness.count(target.seen.looks, slot) ~= 0 then
			return false, `The look entry rode on after {moderator.viewer.key.Name} stopped being a watcher`
		end
	end

	return true, nil
end
