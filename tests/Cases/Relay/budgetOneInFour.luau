--[[
    Under a relay budget of 0, with the viewers' list shuffled every run, each
    run leaves a quarter of them and no viewer is left twice within four runs,
    in process and on 2 stand-in workers
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local VIEWERS: number = 8
local LEFT: number = 2 -- A quarter of them, each run
local EVERY: number = 4 -- No viewer is left in two runs nearer than this
local RUNS: number = 40
local SEED: number = 606
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807

-- Runs the shuffled list under a budget of 0 and gives why it broke the rule, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local names: { [any]: number } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 10, 0, 0)
		names[client.viewer.key] = index
	end

	harness:spawn("Player", vector.create(0, 0, -50))
	Harness.Relay.setBudget(0)

	local value: number = SEED
	local lastLeft: { [number]: number } = {}
	for run: number = 1, RUNS do
		-- A seeded shuffle, so a viewer's place says nothing of when it was last left
		local viewers: { any } = harness.viewers
		for index: number = #viewers, 2, -1 do
			value = value * MULTIPLIER % MODULUS
			local other: number = value % index + 1
			viewers[index], viewers[other] = viewers[other], viewers[index]
		end

		harness:run()

		if #harness.passed ~= LEFT then
			return `Run {run} left {#harness.passed} viewers, not {LEFT}`
		end

		for _, call: any in harness.passed do
			local name: number = names[call.key]
			local last: number? = lastLeft[name]
			if last ~= nil and run - last < EVERY then
				return `Viewer {name} was left on run {last} and again on run {run}`
			end

			lastLeft[name] = run
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = drive(Environment.load(HARNESS), nil)
	if why then
		return false, `In process: {why}`
	end

	why = drive(Layouts.harness(), WORKERS)
	if why then
		return false, `On {WORKERS} workers: {why}`
	end

	return true, nil
end
