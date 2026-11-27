--[[
    A culled enemy heard through footstep entries is sent its record again
    on the very relay tick it is no longer culled, and from then on makes
    no footstep entry
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local STRIDE: number = 0.5
local HEARD_TICKS: number = 20
local SEEN_TICKS: number = 20

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(5, 0, 5))

	harness:hide(client, slot, true)
	harness:run()

	local heard: number = 0
	for _ = 1, HEARD_TICKS do
		harness.states[slot].position += vector.create(STRIDE, 0, 0)
		harness:run()
		heard += #client.seen.footsteps
	end

	if heard == 0 then
		return false, "The culled enemy walking in earshot made no footstep entry"
	end

	harness:hide(client, slot, false)
	harness.states[slot].position += vector.create(STRIDE, 0, 0)
	harness:run()

	local record: any = Harness.find(client.seen.records, slot)
	if Harness.count(client.seen.reveals, slot) ~= 1 or not record then
		return false, "The enemy no longer culled was not revealed with its record on that tick"
	elseif vector.magnitude(record.position - harness.states[slot].position) > QUANTUM then
		return false, "The enemy's record on its reveal is not its place"
	end

	for _ = 1, SEEN_TICKS do
		harness.states[slot].position += vector.create(STRIDE, 0, 0)
		harness:run()

		if #client.seen.footsteps ~= 0 then
			return false, "An enemy the viewer is sent still made footstep entries"
		elseif Harness.count(client.seen.records, slot) ~= 1 then
			return false, "The enemy the viewer is sent stopped getting its records"
		end
	end

	return true, nil
end
