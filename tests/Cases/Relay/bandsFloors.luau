--[[
    With the soft budget spent, a moving player in view in the first band
    falls from its 20 Hz aim to its 15 Hz floor, while those in the second
    and third, whose floors equal their aims, lose no record
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local SETTLE: number = 4 -- Runs before the squeeze, past each target's reveal
local SOFT: number = 64 * 1000 -- The example's soft budget, in bytes a second, which the viewer's traffic is set to
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth, so each always has a change to send
local DISTANCES: { number } = { 100, 450, 800 } -- Studs ahead of the viewer, one inside each band
local EXPECTED: { number } = { 30, 20, 10 } -- The records each got over the squeezed runs

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	-- Facing along -Z, so every target ahead of it is in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	local targets: { number } = {}
	for index: number, distance: number in DISTANCES do
		targets[index] = harness:spawn("Player", vector.create(0, 0, -distance))
	end

	local counts: { number } = table.create(#targets, 0)
	for run: number = 1, SETTLE + RUNS do
		-- No room is left under the soft budget, while the hard budget still has room for every record owed
		if run == SETTLE + 1 then
			harness.traffic = SOFT
		end

		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in targets do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		if run > SETTLE then
			for index: number, slot: number in targets do
				counts[index] += Harness.count(client.seen.records, slot)
			end
		end
	end

	for index: number, expected: number in EXPECTED do
		if counts[index] ~= expected then
			local got: string = `{counts[index]} records over {RUNS} squeezed runs, not {expected}`
			return false, `The player {DISTANCES[index]} studs ahead got {got} ({table.concat(counts, ", ")})`
		end
	end

	return true, nil
end
