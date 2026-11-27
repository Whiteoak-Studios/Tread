--[[
    A pair packed for a worker whose viewer the relay's next run leaves out,
    handed to AntiEsp.passed, is settled when its batch lands, as an asked
    pair is, not released by the landing's round check, so its next ask
    finds its tested verdict
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local STEP: number = 1 / 64

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end, Harness.clock().read)

	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useWhole(true)

	local _, left: any = harness:player("Left", vector.zero)
	local _, other: any = harness:player("Other", vector.create(0, 0, 50))
	local target: number = harness:body("Player", vector.create(20, 0, 0))

	-- Both pairs packed at 0 s with every ray open
	AntiEsp.isHidden(left, target)
	AntiEsp.isHidden(other, target)
	harness:slice(0)

	if #override.made.sends ~= 1 or override.made.sends[1].pairs ~= 2 then
		return false, "Both pairs weren't packed into one batch"
	end

	-- The next run asks for the other viewer and leaves the left one out, then the batch lands
	AntiEsp.isHidden(other, target)
	AntiEsp.passed(left, { target }, 1)
	harness:slice(STEP)

	local tests: number = AntiEsp.counts()
	if tests ~= 2 then
		return false, `{tests} landed tests settled, where the left viewer's kept pair should have been one of 2`
	elseif AntiEsp.reason(left.key, target) ~= "Clear" then
		return false, `The left viewer's kept pair read {AntiEsp.reason(left.key, target)} after its batch landed`
	elseif AntiEsp.isHidden(left, target) then
		return false, "The left viewer's kept pair, seen by its worker, restarted hidden at its next ask"
	end

	return true, nil
end
