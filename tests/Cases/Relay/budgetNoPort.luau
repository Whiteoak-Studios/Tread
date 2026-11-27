--[[
    A relay started with no passed port runs under a budget and leaves its
    viewers with no error, in process and on 2 stand-in workers, calling
    nothing in the port's place
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local VIEWERS: number = 4 -- So each run under a budget of 0 leaves one
local RUNS: number = 8
local PORTLESS: boolean = true -- Harness.new's flag that starts the relay with no passed port

-- Runs the budget's runs and gives why they went wrong, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers, PORTLESS)
	for index: number = 1, VIEWERS do
		harness:viewer(`Viewer{index}`).viewer.position = vector.create(index * 10, 0, 0)
	end

	harness:spawn("Player", vector.create(0, 0, -60))
	Harness.Relay.setBudget(0)

	local ran: boolean, failure: any = pcall(harness.runs, harness, RUNS)
	if not ran then
		return `The runs threw: {failure}`
	end

	local left: number = Harness.Relay.caps()
	if left ~= RUNS then
		return `The budget left {left} viewer turns over {RUNS} runs, not one a run`
	elseif #harness.passed ~= 0 then
		return `A relay with no passed port reached the harness's port {#harness.passed} times`
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
