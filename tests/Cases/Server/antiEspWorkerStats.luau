--[[
    server:stats gives antiEspRays always, and with antiEsp.workers above 0
    the workers' tests, busy time summed and longest, and late batches, each
    as its change since the last read; with no workers, none of the four
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local SLOW: number = 0.001 -- Hz, every recheck rate, so no pair falls due again unless the case makes it
local FAIL_OPEN: number = 1000 -- Seconds, so no batch is given up and no pair fails open while the case runs
local SHARE: number = 0.5 -- A tick's share one short frame owes, so it runs only anti-ESP's slice
local WALL_SIZE: vector = vector.create(1, 40, 40) -- Tall and wide enough to block every ray across it
local BUSY: { number } = { 0.25, 0.5 } -- Seconds each worker's batches report they took
local TICKS: number = 3
local FRAMES: number = 10 -- The most short frames a wait for every batch to land runs
local FIELDS: { string } = { "antiEspWorkerTests", "antiEspWorkerBusy", "antiEspWorkerLongest", "antiEspLateBatches" }

type Built = {
	rig: Rig.Rig,
	server: any,
	AntiEsp: any,
	pool: any,
	slots: { number },
}

-- A server with a wall between its two bots, its rechecks slowed, with that many anti-ESP workers
local function build(workers: number): Built
	local override: { [string]: any } = StandIn.override()
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.antiEsp.slice = 1
		settings.antiEsp.failOpen = FAIL_OPEN
		settings.antiEsp.hiddenRate = SLOW
		settings.antiEsp.nearRate = SLOW
		settings.antiEsp.visibleRate = SLOW
		settings.antiEsp.workers = workers
	end, { [POOL] = override })

	local server: any = rig:start()
	rig:wall(vector.create(3, rig.floor + WALL_SIZE.y / 4, 0), WALL_SIZE)

	local viewer: any = server:create(rig.mock:addBot("Viewer"), rig:at(0, 0))
	local target: any = server:create(rig.mock:addBot("Target"), rig:at(6, 0))

	local pool: any = override.made
	if pool then
		pool.busy[1] = BUSY[1]
		pool.busy[2] = BUSY[2]
	end

	return {
		rig = rig,
		server = server,
		AntiEsp = rig:require(rig.tread.Server.AntiEsp),
		pool = pool,
		slots = { viewer._slot, target._slot },
	}
end

-- Short frames until one sends nothing, so every batch out has landed, giving whether one did within FRAMES
local function settle(built: Built): boolean
	for _ = 1, FRAMES do
		local sent: number = #built.pool.sends
		built.rig.frames:run(SHARE / built.rig.rate)

		if #built.pool.sends == sent then
			return true
		end
	end

	return false
end

return function (): (boolean, string | nil)
	-- 1) No workers: the rays alone
	local plain: Built = build(0)
	plain.server:stats()
	plain.rig:tick(TICKS)

	local read: any = plain.server:stats()
	if type(read.antiEspRays) ~= "number" or not (read.antiEspRays > 0) then
		return false, `With no workers, stats gave antiEspRays {read.antiEspRays} after the pairs were tested`
	end

	for _, field: string in FIELDS do
		if read[field] ~= nil then
			return false, `With no workers, stats gave {field}`
		end
	end

	-- 2) Workers: every batch landed, the figures are the pool's own
	local built: Built = build(WORKERS)
	local pool: any = built.pool
	if pool == nil then
		return false, "Anti-ESP made no pool with antiEsp.workers above 0"
	end

	built.server:stats()
	built.rig:tick(TICKS)
	if not settle(built) then
		return false, `The batches were still being sent after {FRAMES} frames`
	end

	local pairs: number = 0
	local busy: number = 0
	local longest: number = 0
	for _, sent: any in pool.sends do
		pairs += sent.pairs
		busy += BUSY[sent.worker]
		longest = math.max(longest, BUSY[sent.worker])
	end

	read = built.server:stats()
	if pairs == 0 then
		return false, "No batch was sent to the workers"
	elseif read.antiEspWorkerTests ~= pairs or read.antiEspRays ~= #pool.rays then
		local counts: string = `{read.antiEspWorkerTests} worker tests and {read.antiEspRays} rays`
		return false, `Stats gave {counts}, where the batches held {pairs} pairs and cast {#pool.rays} rays`
	elseif read.antiEspWorkerBusy ~= busy or read.antiEspWorkerLongest ~= longest then
		local times: string = `{read.antiEspWorkerBusy} s busy and {read.antiEspWorkerLongest} s longest`
		return false, `Stats gave {times}, not {busy} and {longest}`
	elseif read.antiEspLateBatches ~= 0 then
		return false, `Stats gave {read.antiEspLateBatches} late batches where every one landed on time`
	end

	-- 3) Read straight after, each is 0
	local again: any = built.server:stats()
	for _, field: string in FIELDS do
		if again[field] ~= 0 then
			return false, `A read straight after another gave {field} {again[field]}`
		end
	end

	if again.antiEspRays ~= 0 then
		return false, `A read straight after another gave antiEspRays {again.antiEspRays}`
	end

	-- 4) A batch held two slices past its own and one that fails are the late ones
	pool.held[1] = true
	pool.failing[2] = "a worker that broke on purpose"
	for _, slot: number in built.slots do
		built.AntiEsp.moved(slot)
	end

	built.rig.frames:run(SHARE / built.rig.rate)
	built.rig.frames:run(SHARE / built.rig.rate)
	built.rig.frames:run(SHARE / built.rig.rate)
	pool.held[1] = false

	if not settle(built) then
		return false, `The batches made due again were still being sent after {FRAMES} frames`
	end

	local late: any = built.server:stats()
	if late.antiEspLateBatches ~= 2 then
		return false, `Stats gave {late.antiEspLateBatches} late batches, not the held one and the failed one`
	end

	return true, nil
end
