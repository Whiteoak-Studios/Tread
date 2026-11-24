--[[
    A recheck out across a stall past the fail-open time is given up and sent
    to the other worker, and the ask shows the pair once; neither stale result
    settles anything, and only the test sent after the fail-open hides it
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64
local SLICES: number = 40 -- The most slices the wait for the recheck runs before it fails
local STALE: number = 1 -- The worker holding the recheck that goes stale
local FRESH: number = 2

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
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	local now: number = 0
	pool.wall = Harness.solid

	local function slice()
		harness:slice(now)
		now += STEP
	end

	-- 1) Hidden by its first test, its recheck then sent and held
	AntiEsp.isHidden(viewer, target)
	slice()
	slice()
	pool.held[STALE] = true
	table.clear(pool.sends)

	for _ = 1, SLICES do
		slice()
		if #pool.sends > 0 then
			break
		end

		AntiEsp.isHidden(viewer, target)
	end

	if #pool.sends ~= 1 or pool.sends[1].worker ~= STALE then
		return false, "The pair's recheck was not sent to the first worker"
	end

	-- 2) The next slice comes after a stall: the held batch is given up there and its pair sent to the other worker,
	-- and the ask after it finds the pair untested past the fail-open time, so shows it
	local tests: number = AntiEsp.counts()
	table.clear(pool.sends)
	now += stall - STEP
	slice()

	if #pool.sends ~= 1 or pool.sends[1].worker ~= FRESH then
		return false, "The held batch's pair was not sent to the other worker at the slice after the stall"
	elseif AntiEsp.isHidden(viewer, target) then
		return false, "The pair in flight past the fail-open time was not shown"
	end

	local _, _, failOpens: number = AntiEsp.counts()
	if failOpens ~= 1 then
		return false, `The pair failed open {failOpens} times, not once`
	end

	-- 3) The retest sent before the fail-open lands stale and settles nothing, and the pair goes again
	table.clear(pool.sends)
	slice()

	if AntiEsp.counts() ~= tests then
		return false, "The retest sent before the pair failed open settled a test"
	elseif AntiEsp.isHidden(viewer, target) then
		return false, "The retest sent before the pair failed open hid it"
	elseif #pool.sends ~= 1 or pool.sends[1].worker ~= FRESH then
		return false, "The failed-open pair was not sent again to the idle worker"
	end

	-- 4) The held batch comes back a slice late and changes nothing, and the test sent after the fail-open hides it
	pool.held[STALE] = false
	slice()

	local _, _, after: number = AntiEsp.counts()
	if AntiEsp.counts() ~= tests + 1 then
		return false, `{AntiEsp.counts() - tests} tests settled once both batches came back, not the fresh one's 1`
	elseif not AntiEsp.isHidden(viewer, target) then
		return false, "The fresh result, blocked, did not hide the pair"
	elseif after ~= 1 then
		return false, `The pair failed open {after} times by the end, not once`
	end

	return true, nil
end
