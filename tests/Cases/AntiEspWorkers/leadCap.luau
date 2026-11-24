--[[
    After a stalled Heartbeat a packing slice reaches at most one relay tick
    ahead, not the whole stall, so a visible pair due 0.2 s after the
    stalled slice waits until a slice comes within a relay tick of it
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKER: number = 1
local STEP: number = 1 / 64
local STALLED: number = 0.3 -- Seconds the slice after the stall runs at, the visible recheck 0.2 s after it
local NEAR: number = 0.46 -- And a later slice, within a relay tick of the recheck

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKER
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -40))
	local relayTick: number = 1 / harness.shared.rates.relay
	local recheck: number = 1 / harness.server.antiEsp.visibleRate -- After its first test, aimed at 0

	-- The stalled slice reaches past the recheck uncapped and short of it capped, and the later one reaches it
	if
		not (STALLED + (STALLED - STEP) >= recheck and STALLED + relayTick < recheck and NEAR + relayTick >= recheck)
	then
		return false, "The case's times no longer put the recheck between a capped and an uncapped reach"
	end

	local function ask()
		AntiEsp.isHidden(viewer, target)
	end

	-- 1) Shown by its first test, aimed at 0 and landed at the next slice
	ask()
	harness:slice(0)
	ask()
	harness:slice(STEP)

	if AntiEsp.isHidden(viewer, target) then
		return false, "The open pair was not shown by its first test"
	end

	-- 2) A stall, then a slice whose reach a whole stall ahead would take the recheck early
	table.clear(pool.sends)
	ask()
	harness:slice(STALLED)

	if #pool.sends ~= 0 then
		return false, `The slice after a {STALLED - STEP} s stall packed the recheck due at {recheck} s`
	end

	-- 3) A slice within a relay tick of it packs it
	ask()
	harness:slice(NEAR)

	if #pool.sends ~= 1 then
		return false, `The slice at {NEAR} s, within a relay tick of the recheck, did not pack it`
	end

	return true, nil
end
