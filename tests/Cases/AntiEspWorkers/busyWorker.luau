--[[
    A worker whose batch hasn't landed gets nothing new: what comes due
    meanwhile goes to the other, the held pair's test with it once its batch
    misses its slice, and with both busy the slice casts in process
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64
local HELD: number = 1
local FREE: number = 2

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local first: number = harness:body("Player", vector.create(0, 0, -10))
	local second: number = harness:body("Player", vector.create(0, 0, -20))

	AntiEsp.isHidden(viewer, first)
	AntiEsp.isHidden(viewer, second)
	harness:slice(0)

	if #pool.sends ~= 2 or pool.sends[1].worker ~= HELD or pool.sends[2].worker ~= FREE then
		return false, "The two first pairs did not go one to each worker"
	end

	-- The first worker's batch held back, while two more pairs come due
	pool.held[HELD] = true
	table.clear(pool.sends)

	local third: number = harness:body("Player", vector.create(0, 0, -30))
	local fourth: number = harness:body("Player", vector.create(0, 0, -40))
	local targets: { number } = { first, second, third, fourth }

	-- As the relay asks, about every pair each run, giving the first pair's answer
	local function ask(): boolean
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end

		return AntiEsp.isHidden(viewer, first)
	end

	ask()
	harness:slice(STEP)

	-- The held batch missed its slice, so its pair goes again with the two new ones, to the worker that is free
	local tests: number = AntiEsp.counts()
	if #pool.sends ~= 1 or pool.sends[1].worker ~= FREE or pool.sends[1].pairs ~= 3 then
		return false, "The held pair and the two due while the first worker was busy did not all go to the other"
	elseif tests ~= 1 then
		return false, `{tests} tests settled with the first worker's batch held, not the second worker's 1`
	elseif not ask() then
		return false, "The held pair was shown before any test of it came back"
	end

	-- The held batch comes back too, a slice late, so only the retest's 3 answers settle
	pool.held[HELD] = false
	harness:slice(2 * STEP)

	tests = AntiEsp.counts()
	if tests ~= 4 then
		return false, `{tests} tests had settled once the retest landed and the held batch came back, not 4`
	elseif ask() then
		return false, "The held pair, open on every ray, was still hidden once its retest landed"
	end

	-- Both workers' batches held, and every pair due again: with no worker free the slice casts them in process
	pool.held[HELD] = true
	pool.held[FREE] = true
	table.clear(pool.sends)
	AntiEsp.moved(own)
	ask()
	harness:slice(3 * STEP)

	if #pool.sends ~= WORKERS then
		return false, "The four pairs due again were not sent to both workers"
	end

	table.clear(pool.sends)
	AntiEsp.moved(own)
	ask()
	tests = AntiEsp.counts()
	harness:slice(4 * STEP)

	if #pool.sends ~= 0 or #harness.rays == 0 or AntiEsp.counts() ~= tests + #targets then
		return false, "With both workers busy, the slice sent a batch or did not cast every due test in process"
	end

	return true, nil
end
