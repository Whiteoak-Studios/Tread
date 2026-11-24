--[[
    An open answer that lands after its target was reborn and before the
    relay asks again shows the new life nothing: the answers and the
    reasons read it untested, and the next ask starts it afresh and hidden
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKER: number = 1
local STEP: number = 1 / 64
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row

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

	-- Its first test packed with every ray open, then the target reborn with no ask between
	AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	if #pool.sends ~= 1 then
		return false, "The first test was not packed for the worker"
	end

	harness:reborn(target)
	local tests: number = AntiEsp.counts()
	harness:slice(STEP)

	if AntiEsp.counts() ~= tests + 1 then
		return false, "The open answer did not land"
	end

	-- Before the next ask, nothing reads the old life's answer as the new life's
	local answers: any = AntiEsp.answers({ viewer })
	local byte: number = buffer.readu8(answers.visible, target // BITS)
	if bit32.btest(byte, bit32.lshift(1, target % BITS)) then
		return false, "The answers showed the reborn target from its old life's open answer"
	elseif AntiEsp.reason(viewer.key, target) ~= "Untested" then
		return false, `The reborn target's reason was {AntiEsp.reason(viewer.key, target)}, not Untested`
	end

	-- The next ask starts it afresh and hidden, and the next slice tests the new life
	if not AntiEsp.isHidden(viewer, target) then
		return false, "The next ask showed the reborn target from its old life's open answer"
	end

	table.clear(pool.sends)
	harness:slice(2 * STEP)

	if #pool.sends ~= 1 then
		return false, "The reborn target's new life was not tested at the next slice"
	end

	return true, nil
end
