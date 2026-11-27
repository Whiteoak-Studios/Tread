--[[
    A moving player behind the viewer in the first band and one in the
    second both fall to the out-of-view rate, 5 a second, and once the
    viewer turns to face them each is owed a record on the very next run
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local SETTLE: number = 4 -- Runs before the count starts, past each target's reveal
local PHASE: number = 4 -- The most runs past the count before both have just been sent a record, at 5 a second
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth, so each always has a change to send
local DISTANCES: { number } = { 100, 450 } -- Studs behind the viewer, past the example's out-of-view radius
local EXPECTED: { number } = { 10, 10 } -- The records each got over the runs behind it
local TURNED: vector = vector.create(0, 0, 1) -- The look toward both, opposite its body's facing

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	-- Facing along -Z, so every target along +Z is behind it
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	local targets: { number } = {}
	for index: number, distance: number in DISTANCES do
		targets[index] = harness:spawn("Player", vector.create(0, 0, distance))
	end

	local run: number = 0
	local function step()
		run += 1

		local stride: number = STRIDE
		if run % 2 == 0 then
			stride = -STRIDE
		end

		for _, slot: number in targets do
			harness.states[slot].position += vector.create(stride, 0, 0)
		end

		harness:run()
	end

	-- Whether every target got a record on the run just taken
	local function allSent(): boolean
		for _, slot: number in targets do
			if Harness.count(client.seen.records, slot) == 0 then
				return false
			end
		end

		return true
	end

	for _ = 1, SETTLE do
		step()
	end

	local counts: { number } = table.create(#targets, 0)
	for _ = 1, RUNS do
		step()
		for index: number, slot: number in targets do
			counts[index] += Harness.count(client.seen.records, slot)
		end
	end

	for index: number, expected: number in EXPECTED do
		if counts[index] ~= expected then
			local got: string = `{counts[index]} records over {RUNS} runs behind the viewer, not {expected}`
			return false, `The player {DISTANCES[index]} studs behind got {got} ({table.concat(counts, ", ")})`
		end
	end

	-- From a run that sent both a record, so at their bands' rates in view the second's isn't due on the next
	local phased: boolean = allSent()
	for _ = 1, PHASE do
		if phased then
			break
		end

		step()
		phased = allSent()
	end

	if not phased then
		return false, `No run in {PHASE} past the count sent both players a record together`
	end

	client.viewer.look = TURNED
	step()

	for index: number, slot: number in targets do
		if Harness.count(client.seen.records, slot) == 0 then
			return false, `The player {DISTANCES[index]} studs out got no record on the run after the viewer turned`
		end
	end

	return true, nil
end
