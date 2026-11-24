--[[
    A viewer the relay budget leaves one run in four keeps its 10 Hz and 5 Hz
    bands at their rates, each record at most a run late, and gets its first
    band 3 runs in 4, the band's 15 Hz floor
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local VIEWERS: number = 4 -- So each run leaves one, and the first viewer waits on runs 4, 8 and on
local FROM: number = 9 -- The first run counted, past the reveals and two of the viewer's waits
local RUNS: number = 48 -- The last, 40 runs or ten waits later
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local AWAY: vector = vector.create(3000, 0, 0) -- Where the other viewers stand, past every target's relevancy

-- One target in each of the dev place's three bands from the viewer at the origin, and its records over the 40 runs:
-- the first band on every run the viewer takes, 30, the 10 Hz band on every other run, 20, and the 5 Hz band on every
-- fourth, 10
local TARGETS: { { name: string, at: vector, records: number } } = {
	{ name = "first band", at = vector.create(0, 0, -100), records = 30 },
	{ name = "10 Hz band", at = vector.create(0, 0, -450), records = 20 },
	{ name = "5 Hz band", at = vector.create(0, 0, -800), records = 10 },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	local viewer: any = harness:viewer("Viewer")
	for index: number = 2, VIEWERS do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local slots: { number } = {}
	for index: number, target: { name: string, at: vector, records: number } in TARGETS do
		slots[index] = harness:spawn("Player", target.at)
	end

	Harness.Relay.setBudget(0)

	local counted: { number } = { 0, 0, 0 }
	local waited: number = 0
	for run: number = 1, RUNS do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		local left: boolean = false
		for _, call: any in harness.passed do
			if call.key == viewer.viewer.key then
				left = true
			end
		end

		if left ~= (run % VIEWERS == 0) then
			return false, `The viewer was left {left} on run {run}, where it waits on every fourth`
		end

		if run >= FROM then
			if left then
				waited += 1
			end

			for index: number, slot: number in slots do
				counted[index] += Harness.count(viewer.seen.records, slot)
			end
		end
	end

	for index: number, target: { name: string, at: vector, records: number } in TARGETS do
		if counted[index] ~= target.records then
			return false,
				`The {target.name}'s target sent {counted[index]} records over {RUNS - FROM + 1} runs with {waited} waits, not {target.records}`
		end
	end

	return true, nil
end
