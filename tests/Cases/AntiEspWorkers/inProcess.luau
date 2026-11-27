--[[
    With workers on and none ready, a slice casts its tests in process and
    settles them at once, sending nothing; once a worker is ready the next
    slice packs for it instead and casts nothing in process
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local TARGETS: number = 3
local SPACING: number = 10 -- Studs between the targets along -Z
local STEP: number = 1 / 64

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	pool.readyCount = 0

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for index: number = 1, TARGETS do
		table.insert(targets, harness:body("Player", vector.create(0, 0, -index * SPACING)))
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- 1) No worker ready: every due test cast here and settled in its own slice
	ask()
	harness:slice(0)

	local tests: number = AntiEsp.counts()
	if not AntiEsp.workersOn() then
		return false, "With antiEsp.workers above 0 the switch started off"
	elseif #pool.sends ~= 0 then
		return false, `With no worker ready {#pool.sends} batches were sent`
	elseif tests ~= TARGETS or #harness.rays == 0 then
		return false, `With no worker ready the slice settled {tests} of {TARGETS} tests from {#harness.rays} rays`
	end

	-- 2) A worker ready: the next slice's due tests go to it, none cast here
	pool.readyCount = 1
	ask()
	AntiEsp.moved(own)
	harness:slice(STEP)

	if #pool.sends ~= 1 or pool.sends[1].worker ~= 1 or pool.sends[1].pairs ~= TARGETS then
		return false, "With one worker ready the due tests were not all sent to it"
	elseif #harness.rays ~= 0 or AntiEsp.counts() ~= tests then
		return false, `With one worker ready {#harness.rays} rays were cast in process`
	end

	-- 3) It lands at the next slice
	ask()
	harness:slice(2 * STEP)

	if AntiEsp.counts() ~= tests + TARGETS then
		return false, "The worker's batch did not settle its tests at the next slice"
	end

	return true, nil
end
