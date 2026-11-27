--[[
    With the out-of-view rate on, moving players near a viewer looking along
    -Z go every relay tick inside its cone and inside the radius behind it,
    and at the out-of-view rate outside the cone past the radius, for a
    cone of 60 degrees, one wider than a quarter turn and one of 180
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local RELAY: number = 20 -- The example's relay rate
local RATE: number = 5 -- Hz, the out-of-view rate the case sets
local RADIUS: number = 15
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth along X, so each changes every run
local LOOK: vector = vector.create(0, 0, -1)
local NARROW: number = 60 -- Degrees either side of the look
local WIDE: number = 120
local WHOLE: number = 180

-- Every run: the reveal's record on the first, then the near tier's aim of a record each run
local EVERY: number = RUNS

-- The reveal's record on the first run, then one each time the credit, from 0 after it, gains RATE / RELAY a run and
-- reaches 1, from the second run on: on runs 1, 5, 9 and so on
local LOWERED: number = 1 + (RUNS - 1) // (RELAY / RATE)

type Target = { name: string, at: vector, expected: number }

-- Each target's records over the runs with the viewer's cone at a half-angle, or why one is off
local function drive(cone: number, targets: { Target }): string?
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.outOfView = { rate = RATE, cone = cone, radius = RADIUS }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = LOOK

	local slots: { number } = {}
	for index: number, target: Target in targets do
		slots[index] = harness:spawn("Player", target.at)
	end

	local counts: { number } = table.create(#targets, 0)
	for run: number = 1, RUNS do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		for index: number, slot: number in slots do
			counts[index] += Harness.count(client.seen.records, slot)
		end
	end

	for index: number, target: Target in targets do
		if counts[index] ~= target.expected then
			return `At a cone of {cone} the player {target.name} got {counts[index]} records, not {target.expected}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- All inside the near tier, so each would go every run without the out-of-view rate
	local problem: string? = drive(NARROW, {
		{ name = "in front", at = vector.create(0, 0, -100), expected = EVERY },
		{ name = "behind", at = vector.create(0, 0, 100), expected = LOWERED },
		{ name = "to the side", at = vector.create(100, 0, 0), expected = LOWERED },
		{ name = "behind inside the radius", at = vector.create(0, 0, 10), expected = EVERY },
	})

	if problem then
		return false, problem
	end

	-- Wider than a quarter turn the side is inside, and three-eighths of a turn round is not
	problem = drive(WIDE, {
		{ name = "to the side", at = vector.create(100, 0, 0), expected = EVERY },
		{ name = "behind to the side", at = vector.create(100, 0, 100), expected = LOWERED },
		{ name = "behind", at = vector.create(0, 0, 100), expected = LOWERED },
	})

	if problem then
		return false, problem
	end

	problem = drive(WHOLE, {
		{ name = "behind", at = vector.create(0, 0, 100), expected = EVERY },
	})

	if problem then
		return false, problem
	end

	return true, nil
end
