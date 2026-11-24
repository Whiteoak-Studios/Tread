--[[
    A batch back at the first slice after a relay hold is on time, as a hold
    runs no slice, so its answer is applied there though the hold outlasted a
    relay interval
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local STEP: number = 1 / 64
local HELD_STEPS: number = 6 -- Steps the relay hold lasts, past a relay interval and inside the fail-open time
local TARGET: vector = vector.create(0, 0, -40)

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local held: number = HELD_STEPS * STEP
	local relay: number = 1 / harness.shared.rates.relay
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)

	if not (held > relay and held < harness.server.antiEsp.failOpen) then
		return false, "The case's hold no longer outlasts a relay interval inside the fail-open time"
	end

	-- 1) Its first test sent, open on every ray
	AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	if #pool.sends ~= 1 then
		return false, "The pair's first test was not sent to the worker"
	end

	-- 2) A relay round holds anti-ESP, asking inside the hold, and no slice runs until it is released
	AntiEsp.hold()
	AntiEsp.isHidden(viewer, target)
	AntiEsp.release()

	-- 3) The first slice after it lands the batch on time, and its open answer shows the pair
	table.clear(pool.sends)
	harness:slice(held)

	local tests: number, _, failOpens: number = AntiEsp.counts()
	if tests ~= 1 then
		return false, `{tests} tests settled at the first slice after the hold, not the batch's 1`
	elseif #pool.sends ~= 0 then
		return false, "The batch back at the first slice after the hold was given up and its pair sent again"
	elseif AntiEsp.isHidden(viewer, target) then
		return false, "The batch's open answer, back at the first slice after the hold, did not show the pair"
	elseif failOpens ~= 0 then
		return false, `{failOpens} pairs failed open across the hold`
	end

	return true, nil
end
