--[[
    A block the viewer never read is never a baseline: the change after a
    lost one is measured from the last record the viewer acknowledged, two
    relay ticks back, and the one after that from the block it did read
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local STEP: vector = vector.create(0.5, 0, 0) -- What the target walks a run, so it has a record every run

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]

	-- The reveal's whole record, acknowledged at once, then a change against it
	harness:runs(2)
	local first: any = Harness.find(client.seen.changes, slot)
	if not first or first.base ~= 1 then
		return false, "The run after the reveal's acknowledgment sent no change against it"
	end

	-- This run's block is lost, so its record never becomes the baseline
	client.lose = 1
	state.position += STEP
	harness:run()

	if client.seen.lost ~= 1 or #client.seen.records ~= 0 then
		return false, `The lost run was read as {#client.seen.records} records and {client.seen.lost} lost blocks`
	end

	state.position += STEP
	harness:run()

	local after: any = Harness.find(client.seen.changes, slot)
	if not after then
		return false, "The run after the lost block sent the record whole"
	elseif after.base ~= 2 then
		return false, `The change after the lost block was against {after.base} ticks back, not the 2 acknowledged`
	end

	state.position += STEP
	harness:run()

	local resumed: any = Harness.find(client.seen.changes, slot)
	if not resumed or resumed.base ~= 1 then
		return false, "Once the block after the loss was acknowledged, the change was not against it"
	end

	return true, nil
end
