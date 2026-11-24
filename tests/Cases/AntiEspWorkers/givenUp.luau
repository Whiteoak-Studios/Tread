--[[
    A hidden pair's open recheck back at the next slice, which a stall puts
    past the fail-open time, is given up there, not applied: the pair stays
    hidden, is tested again at once, and the given-up batch's rays are counted
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local STEP: number = 1 / 64
local SLICES: number = 40 -- The most slices the wait for the recheck runs before it fails
local TARGET: vector = vector.create(0, 0, -300) -- Past the example's near radius, on its 10 Hz recheck

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local stall: number = harness.server.antiEsp.failOpen + STEP
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)
	pool.wall = Harness.solid

	-- 1) Hidden by its first test on the worker
	AntiEsp.isHidden(viewer, target)
	harness:slice(0)
	harness:slice(STEP)

	if AntiEsp.reason(viewer.key, target) ~= "Hidden" then
		return false, "The pair behind the wall was not hidden by its first test"
	end

	-- 2) Its recheck sent while the wall is open, the wall then closed; no ask follows, so none fails open
	pool.wall = Harness.open
	table.clear(pool.sends)

	local sentAt: number? = nil
	for slice: number = 2, SLICES do
		harness:slice(slice * STEP)
		if #pool.sends > 0 then
			sentAt = slice * STEP
			break
		end
	end

	if sentAt == nil then
		return false, "The pair's recheck was never sent"
	end

	pool.wall = Harness.solid
	local tests: number = AntiEsp.counts()

	-- 3) Back by the next slice, which comes after a stall, so past the fail-open time, where the collect gives it up
	AntiEsp.rays()
	table.clear(pool.sends)
	harness:slice(sentAt + stall)

	if AntiEsp.counts() ~= tests then
		return false, `The batch back past the fail-open time settled {AntiEsp.counts() - tests} tests`
	elseif AntiEsp.reason(viewer.key, target) ~= "Hidden" then
		return false, `The batch back past the fail-open time left the pair {AntiEsp.reason(viewer.key, target)}`
	elseif AntiEsp.rays() ~= 1 then
		return false, "The given-up batch's one open ray was not counted"
	elseif #pool.sends ~= 1 then
		return false, "The given-up pair was not sent again at once"
	end

	-- 4) Its fresh test, under the closed wall, keeps it hidden
	harness:slice(sentAt + stall + STEP)

	if AntiEsp.counts() ~= tests + 1 or AntiEsp.reason(viewer.key, target) ~= "Hidden" then
		return false, "The fresh test of the given-up pair did not settle it hidden"
	end

	return true, nil
end
