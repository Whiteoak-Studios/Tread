--[[
    A turn after a run the relay budget left its viewer, with relay ticks
    skipped besides, counts every tick since its last turn but holds each
    pair's credit to 2 band ticks, so a 10 Hz target's records after the
    gap come as a short burst, not one as long as the gap
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local VIEWERS: number = 4 -- So under a budget of 0 the first viewer waits on the fourth run
local LEFT_RUN: number = 4
local SKIPPED: number = 4 -- Relay ticks skipped before the run after it, so its turn comes 6 ticks after its last
local COUNTED: number = 5 -- Runs counted from that turn
local STRIDE: number = 0.1 -- Studs the target moves a run, back and forth, so it always has a change to send
local TARGET_AT: vector = vector.create(0, 0, -450) -- In the 10 Hz band, half a band tick a relay tick
local AWAY: vector = vector.create(3000, 0, 0)

-- The target's records on the five runs from the turn after the wait: its credit of none at the wait takes the six
-- ticks' 3 band ticks held to 2, so a record on each of three runs, none on the fourth and one on the fifth, where the
-- whole 3 would have given one on all five
local EXPECTED: string = "11101"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	local viewer: any = harness:viewer("Viewer")
	for index: number = 2, VIEWERS do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local target: number = harness:spawn("Player", TARGET_AT)
	Harness.Relay.setBudget(0)

	local records: { string } = {}
	for run: number = 1, LEFT_RUN + COUNTED do
		harness.states[target].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)

		-- After the wait no budget is set, so the gap's ticks are all the turn's credit has to say of it
		if run == LEFT_RUN + 1 then
			Harness.Relay.setBudget(nil)
			harness.tick += SKIPPED
		end

		harness:run()

		local waited: boolean = false
		for _, call: any in harness.passed do
			waited = waited or call.key == viewer.viewer.key
		end

		if waited ~= (run == LEFT_RUN) then
			return false, `The viewer was left {waited} on run {run}, where it waits on run {LEFT_RUN} alone`
		end

		if run > LEFT_RUN then
			table.insert(records, `{Harness.count(viewer.seen.records, target)}`)
		end
	end

	local ran: string = table.concat(records)
	if ran ~= EXPECTED then
		return false, `The 10 Hz target's records after the gap ran {ran}, not {EXPECTED}`
	end

	return true, nil
end
