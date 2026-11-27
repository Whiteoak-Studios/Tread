--[[
    A slice that packs for a worker starts packing no test that the mean of
    those it packed says would end past its budget, sends those it packed,
    and packs its first on a budget shorter than one test
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local SPIN: number = 0.004 -- Seconds of os.clock each slowed target's aim takes, read once a test
local BUDGET: number = 2.5 * SPIN -- Two tests' mean ends inside it, and a third would start inside it and end past it
local SHORT: number = 0.75 * SPIN -- A budget shorter than one test
local TOLERANCE: number = 0.25 * SPIN -- Seconds the case's own clock reads may sit from the slice's
local PLAYERS: number = 6
local SPACING: number = 10 -- Studs between neighboring players along X
local FIRST: number = 0.05 -- Seconds on, at the measured slices
local SECOND: number = 0.1

--[[
    A target's state whose posture, which only aiming its test reads, holds
    the thread for SPIN seconds of os.clock first, noting when it began
--]]

local function slowed(state: any, starts: { number }): any
	return setmetatable({}, {
		__index = function (_: any, field: string): any
			if field == "posture" then
				local began: number = os.clock()
				table.insert(starts, began)

				while os.clock() < began + SPIN do
					continue
				end
			end

			return state[field]
		end,
	})
end

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
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

	-- When each slowed aim started, one a test
	local starts: { number } = {}

	ask()
	harness:slice(0)
	ask()
	AntiEsp.moved(own)

	for _, target: number in targets do
		harness.states[target] = slowed(harness.states[target], starts)
	end

	table.clear(pool.sends)
	local opened: number = os.clock()
	harness:slice(FIRST, BUDGET)

	if #starts == 0 or #starts >= PLAYERS then
		return false, `A slice with {PLAYERS} tests due and room for a few packed {#starts}`
	elseif #pool.sends ~= 1 or pool.sends[1].pairs ~= #starts then
		return false, `The slice packed {#starts} tests and did not send them all in one batch`
	end

	-- The mean as the case's clock gives it is never below the slice's own, and its deadline never later
	for index: number = 2, #starts do
		local start: number = starts[index]
		local predicted: number = start + (start - opened) / (index - 1)

		if predicted > opened + BUDGET + TOLERANCE then
			local past: number = predicted - opened - BUDGET
			return false, `Test {index} was packed where the mean of those before put its end {past} s past the budget`
		end
	end

	-- A budget shorter than one test still packs the slice's first
	ask()
	AntiEsp.moved(own)
	table.clear(starts)
	table.clear(pool.sends)
	harness:slice(SECOND, SHORT)

	if #starts ~= 1 or #pool.sends ~= 1 or pool.sends[1].pairs ~= 1 then
		return false, `A slice whose budget is shorter than one test packed {#starts} tests, not its first alone`
	end

	return true, nil
end
