--[[
    A batch that lands as failure text has its pairs sent again to the
    other worker, and that worker is sent nothing more; with the other busy,
    or both failed, every slice casts its due tests in process
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local BROKEN: number = 1
local OTHER: number = 2
local FAILURE: string = "a worker that broke on purpose"
local TARGETS: number = 3
local SPACING: number = 10 -- Studs between the targets along -Z
local STEP: number = 1 / 64
local AFTER: number = 6 -- Slices run after the failure, each with every pair due again

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
	for index: number = 1, TARGETS do
		table.insert(targets, harness:body("Player", vector.create(0, 0, -index * SPACING)))
	end

	-- One slice after the relay's asks, with every pair made due again first when moving, which drops what is out
	local slice: number = 0
	local function advance(moving: boolean)
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end

		if moving then
			AntiEsp.moved(own)
		end

		table.clear(pool.sends)
		table.clear(harness.rays)
		harness:slice(slice * STEP)
		slice += 1
	end

	-- 1) The first batches: the broken worker's lands as failure text
	pool.failing[BROKEN] = FAILURE
	advance(false)

	local brokenPairs: number = 0
	for _, sent: any in pool.sends do
		if sent.worker == BROKEN then
			brokenPairs += sent.pairs
		end
	end

	if #pool.sends ~= WORKERS or brokenPairs == 0 then
		return false, "The first slice did not send a batch to each worker"
	end

	-- 2) Its pairs go to the other worker in the slice its failure lands, beside the other's own landing
	advance(false)

	local tests: number = AntiEsp.counts()
	if #pool.sends ~= 1 or pool.sends[1].worker ~= OTHER or pool.sends[1].pairs ~= brokenPairs then
		return false, "The failed batch's pairs were not sent to the other worker alone"
	elseif tests ~= TARGETS - brokenPairs then
		return false, `{tests} tests settled, where the failed batch's {brokenPairs} pairs settle none`
	end

	-- 3) From then on the broken worker is sent nothing, with every pair due each slice
	for _ = 1, AFTER do
		advance(true)

		for _, sent: any in pool.sends do
			if sent.worker == BROKEN then
				return false, "The worker whose batch failed was sent another"
			end
		end

		if #pool.sends ~= 1 or #harness.rays ~= 0 then
			return false, "With one worker left, a slice sent no batch to it or cast in process"
		end
	end

	-- 4) The other held: with no worker free, each slice casts its due tests in process
	pool.held[OTHER] = true
	advance(true)

	tests = AntiEsp.counts()
	advance(true)

	if #pool.sends ~= 0 or #harness.rays == 0 or AntiEsp.counts() ~= tests + TARGETS then
		return false, "With the one worker left busy, a slice sent a batch or did not cast its due tests in process"
	end

	-- 5) Its next batch fails too: every slice after casts in process
	pool.held[OTHER] = false
	pool.failing[OTHER] = FAILURE
	advance(true)
	advance(true)

	tests = AntiEsp.counts()
	advance(true)

	if #pool.sends ~= 0 or #harness.rays == 0 or AntiEsp.counts() ~= tests + TARGETS then
		return false, "With both workers failed, a slice did not cast every due test in process"
	end

	return true, nil
end
