--[[
    A round out on a stand-in worker when Relay.setBudget or
    Relay.setUnderLoad is called is neither measured nor judged: its finish
    reads no clock, counts no run over, sets no hand-in for the next run and
    adds nothing to the far rate under load's fresh count
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local VIEWERS: number = 4 -- So a run may leave 1
local BUDGET: number = 1 -- Stand-in seconds, which a worker run's two reads of STEP pass
local FRESH: number = 2 -- The budget set while the round is out, which they pass too
local STEP: number = 2
local UNDER_LOAD: { runs: number, scale: number } = { runs = 2, scale = 0.5 }
local AFTER: number = 3 -- Runs over after the second call: the farthest band lowered on the third alone

return function (): (boolean, string | nil)
	local Harness: any = Layouts.harness()
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay
	for index: number = 1, VIEWERS do
		harness:viewer(`Viewer{index}`).viewer.position = vector.create(index * 10, 0, 0)
	end

	harness.step = STEP
	Relay.setBudget(BUDGET)
	harness:run()

	-- A run out when a fresh budget is set: its own measure would have the next hand in 4 x 1 / 4 = 1 turn of 4
	local function dispatch()
		harness.passed = {}
		harness.tick += 1
		Relay.run(harness.tick, harness.viewers, harness.states, harness.commands, harness.platforms)
	end

	dispatch()
	Relay.setBudget(FRESH)

	local reads: number = harness.reads
	local _, before: number = Relay.caps()
	harness.pool:deliver()
	Relay.finish()

	local _, over: number = Relay.caps()
	if harness.reads ~= reads or over ~= before then
		return false,
			`A round out at Relay.setBudget read the clock {harness.reads - reads} times at its finish and judged {over - before} runs`
	end

	harness:run()
	if #harness.passed ~= 0 then
		return false, `The run after a fresh budget left {#harness.passed} viewers, as the old round's measure would`
	end

	-- A run out when the far rate under load is set: its verdict stays out of the count the call starts afresh
	dispatch()
	Relay.setUnderLoad(UNDER_LOAD)

	reads = harness.reads
	_, before = Relay.caps()
	harness.pool:deliver()
	Relay.finish()

	_, over = Relay.caps()
	if harness.reads ~= reads or over ~= before then
		return false,
			`A round out at Relay.setUnderLoad read the clock {harness.reads - reads} times at its finish and judged {over - before} runs`
	end

	harness:runs(AFTER)

	local _, _, halved: number = Relay.caps()
	if halved ~= 1 then
		return false, `After {AFTER} runs over the far band was lowered on {halved} runs, not on the third alone`
	end

	return true, nil
end
