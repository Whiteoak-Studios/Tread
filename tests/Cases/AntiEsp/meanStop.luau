--[[
    A slice starts no test that the mean of the tests it has run says would
    end past its budget, so a test that would start inside the budget and
    end past it is left for the next slice, and the slice's first test runs
    on a budget shorter than one test
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SPIN: number = 0.004 -- Seconds of os.clock each slow ray takes; a test casts one, as its first ray is open
local BUDGET: number = 2.5 * SPIN -- Two tests' mean ends inside it, and a third would start inside it and end past it
local SHORT: number = 0.75 * SPIN -- A budget shorter than one test
local TOLERANCE: number = 0.25 * SPIN -- Seconds the case's own clock reads may sit from the slice's
local PLAYERS: number = 6
local SPACING: number = 10 -- Studs between neighboring players along X
local FIRST: number = 0.05 -- Seconds on, at the measured slices
local SECOND: number = 0.1

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}

	for index: number = 1, PLAYERS do
		table.insert(targets, harness:body("Player", vector.create(SPACING * index, 0, 0)))
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- When each slow ray started, one a test
	local starts: { number } = {}
	local function slow(_: vector, _: vector): boolean
		local began: number = os.clock()
		table.insert(starts, began)

		while os.clock() < began + SPIN do
			continue
		end

		return false
	end

	ask()
	harness:slice(0)
	ask()
	AntiEsp.moved(own)
	harness.wall = slow

	local opened: number = os.clock()
	harness:slice(FIRST, BUDGET)

	if #starts == 0 or #starts >= PLAYERS then
		return false, `A slice with {PLAYERS} tests due and room for a few ran {#starts}`
	end

	-- The mean as the case's clock gives it is never below the slice's own, and its deadline never later
	for index: number = 2, #starts do
		local start: number = starts[index]
		local predicted: number = start + (start - opened) / (index - 1)

		if predicted > opened + BUDGET + TOLERANCE then
			local past: number = predicted - opened - BUDGET
			return false, `Test {index} started where the mean of those before put its end {past} s past the budget`
		end
	end

	-- A budget shorter than one test still runs the slice's first
	ask()
	AntiEsp.moved(own)
	table.clear(starts)
	harness:slice(SECOND, SHORT)

	if #starts ~= 1 then
		return false, `A slice whose budget is shorter than one test ran {#starts} tests, not its first alone`
	end

	return true, nil
end
