--[[
    Relay.caps gives the frame caps' running totals, in process and on 2
    stand-in workers: the viewer turns the budget left, the runs over it, and
    the runs taken with the farthest band lowered, each standing still once
    its cap is taken off
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local VIEWERS: number = 4 -- So each run under a budget of 0 leaves one, and every such run is over
local UNDER_LOAD: { runs: number, scale: number } = { runs = 2, scale = 0.5 }

-- Each phase's runs and the totals after them: under both caps, the band lowered from the third run; then the budget
-- alone; then neither
local PHASES: { { runs: number, left: number, over: number, halved: number } } = {
	{ runs = 6, left = 6, over = 6, halved = 4 },
	{ runs = 2, left = 8, over = 8, halved = 4 },
	{ runs = 2, left = 8, over = 8, halved = 4 },
}

-- Runs the phases and gives why a total went wrong, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay
	for index: number = 1, VIEWERS do
		harness:viewer(`Viewer{index}`).viewer.position = vector.create(index * 10, 0, 0)
	end

	harness:spawn("Player", vector.create(0, 0, -300))

	local left: number, over: number, halved: number = Relay.caps()
	if left + over + halved ~= 0 then
		return `Relay.caps gave {left}, {over} and {halved} before any cap was set`
	end

	for phase: number, planned: { runs: number, left: number, over: number, halved: number } in PHASES do
		if phase == 1 then
			Relay.setBudget(0)
			Relay.setUnderLoad(UNDER_LOAD)
		elseif phase == 2 then
			Relay.setUnderLoad(nil)
		else
			Relay.setBudget(nil)
		end

		harness:runs(planned.runs)

		left, over, halved = Relay.caps()
		if left ~= planned.left or over ~= planned.over or halved ~= planned.halved then
			return `After phase {phase} Relay.caps gave {left}, {over} and {halved}, not {planned.left}, {planned.over} and {planned.halved}`
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
