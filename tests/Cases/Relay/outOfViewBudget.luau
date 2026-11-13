--[[
    Past the soft budget the players in the viewer's view lose their fills
    down to their floor, while a player held to the out-of-view rate keeps
    every record that rate owes it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40
local RELAY: number = 20 -- The example's relay rate
local RATE: number = 5 -- Hz, the out-of-view rate the case sets
local CONE: number = 60
local RADIUS: number = 15
local SOFT: number = 64 * 1000 -- The example's soft budget, in bytes a second
local STRIDE: number = 0.1
local AHEAD: vector = vector.create(0, 0, -1)

-- The reveal's record, then one each fourth run, every one owed at its floor
local LOWERED: number = 1 + (RUNS - 1) // (RELAY / RATE)

-- The reveal's record, then at the near floor of 15 Hz three of every four runs from run 2 on, each as the floor's
-- credit reaches 1: runs 3 to 5, 7 to 9 and so on, to 39 and 40, with every fill between cut
local FLOORED: number = 30

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.outOfView = { rate = RATE, cone = CONE, radius = RADIUS }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = AHEAD

	local behind: number = harness:spawn("Player", vector.create(0, 0, 500))
	local inView: { number } = {
		harness:spawn("Player", vector.create(0, 0, -50)),
		harness:spawn("Player", vector.create(10, 0, -60)),
		harness:spawn("Player", vector.create(-10, 0, -70)),
	}

	local slots: { number } = table.clone(inView)
	table.insert(slots, behind)

	-- The viewer's tick has no soft room at all, and hard room to spare
	harness.traffic = SOFT + 1

	local counts: { [number]: number } = {}
	for run: number = 1, RUNS do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		for _, slot: number in slots do
			counts[slot] = (counts[slot] or 0) + Harness.count(client.seen.records, slot)
		end
	end

	if counts[behind] ~= LOWERED then
		return false, `In the squeeze the player behind got {counts[behind]} records, not the {LOWERED} its rate owes`
	end

	for _, slot: number in inView do
		if counts[slot] ~= FLOORED then
			return false, `In the squeeze a player in view got {counts[slot]} records, not its floor's {FLOORED}`
		end
	end

	return true, nil
end
