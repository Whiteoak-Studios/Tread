--[[
    A pair the relay left out of its last run while its test was in flight,
    or whose target left the states, is released when its result lands,
    untested, so the next ask starts it afresh and hidden
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local first: number = harness:body("Player", vector.create(0, 0, -30))
	local second: number = harness:body("Player", vector.create(0, 0, -40))

	-- Both packed with every ray open, and the relay's next run asks about the second alone
	AntiEsp.isHidden(viewer, first)
	AntiEsp.isHidden(viewer, second)
	harness:slice(0)
	AntiEsp.isHidden(viewer, second)
	harness:slice(STEP)

	local tests: number = AntiEsp.counts()
	if tests ~= 1 then
		return false, `{tests} tests settled, where the pair left out of the relay's run should have been dropped`
	elseif not AntiEsp.isHidden(viewer, first) then
		return false, "The pair left out of the relay's run took its open result"
	elseif AntiEsp.isHidden(viewer, second) then
		return false, "The pair the relay still asked about lost its open result"
	end

	-- Its new pair packed, and its target gone from the states before the result lands
	harness:slice(2 * STEP)
	local body: any = harness.states[first]
	harness.states[first] = nil
	AntiEsp.isHidden(viewer, first)
	AntiEsp.isHidden(viewer, second)
	harness:slice(3 * STEP)

	harness.states[first] = body
	tests = AntiEsp.counts()

	if tests ~= 1 then
		return false, `{tests} tests settled, where the pair whose target went should have been dropped`
	elseif not AntiEsp.isHidden(viewer, first) then
		return false, "The pair whose target went while in flight took its open result"
	end

	return true, nil
end
