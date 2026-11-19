--[[
    Two viewers sharing a baseline get the same change bytes, the change of
    that target and base encoded once a run for both, while a third whose
    acknowledgments run later gets its change against its own baseline
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 12
local LATE: number = 2 -- Runs the third viewer's acknowledgments take
local STEP: vector = vector.create(0.25, 0.1, -0.5) -- What the target walks a run, so it has a record every run
local TURN: number = 0.1 -- Radians its facing turns a run

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	local first: any = harness:viewer("First")
	local second: any = harness:viewer("Second")
	local late: any = harness:viewer("Late")
	late.lag = LATE

	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]
	local shared: number = 0

	for run: number = 1, RUNS do
		state.position += STEP
		state.facing += TURN
		harness:run()

		local a: any = Harness.find(first.seen.changes, slot)
		local b: any = Harness.find(second.seen.changes, slot)
		local c: any = Harness.find(late.seen.changes, slot)

		if (a == nil) ~= (b == nil) then
			return false, `On run {run} one of two viewers sharing a baseline got a change and the other didn't`
		elseif a and (a.bytes ~= b.bytes or a.base ~= b.base) then
			return false, `On run {run} two viewers sharing a baseline got different change bytes`
		elseif a and c and c.base ~= a.base + LATE then
			return false, `On run {run} the late viewer's change named {c.base} ticks back, not its own {a.base + LATE}`
		end

		if a then
			shared += 1
		end
	end

	if shared < RUNS - 1 then
		return false, `The two viewers sharing a baseline got changes on only {shared} of {RUNS} runs`
	end

	return true, nil
end
