--[[
    A still scene of 3 viewers and 6 targets behind a wall gives the same
    verdict for every pair at every slice from the second on 2 and on 3
    workers as in process, the same rays bit for bit a slice early, every
    worker used
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local STEP: number = 1 / 64 -- Seconds between slices, exact in binary, so every run's due times fall alike
local SLICES: number = 48 -- Past a visible pair's 2 Hz recheck
local RAY_FORMAT: string = "<ffffff" -- A ray's origin and direction, each component's f32 bits

-- A wall across z = -50 from x = -200 to 10.5, as tall as any ray
local WALL_Z: number = -50
local WALL_LEFT: number = -200
local WALL_RIGHT: number = 10.5

local VIEWERS: { vector } = { vector.create(0, 0, 0), vector.create(60, 0, 0), vector.create(-60, 0, 0) }

type Target = { kind: string, at: vector }

local TARGETS: { Target } = {
	{ kind = "Player", at = vector.create(-100, 0, -100) },
	{ kind = "Player", at = vector.create(-20, 0, -100) },
	{ kind = "Player", at = vector.create(20, 0, -100) }, -- Seen from the origin past the wall's end by a side ray
	{ kind = "Player", at = vector.create(100, 0, -100) },
	{ kind = "Sleeper", at = vector.create(-40, 0, -80) },
	{ kind = "Body", at = vector.create(40, 0, -80) },
}

type Run = {
	verdicts: { { boolean } }, -- Each slice's, every pair's in viewer then target order
	rays: { [string]: number }, -- Each ray cast, by its bits, and how many times
	workers: { [number]: boolean }, -- The workers sent a batch
	inProcess: number, -- Rays cast in process on a run with workers
}

-- Whether a ray crosses the wall
local function wall(origin: vector, direction: vector): boolean
	if direction.z == 0 then
		return false
	end

	local along: number = (WALL_Z - origin.z) / direction.z
	if along < 0 or along > 1 then
		return false
	end

	local x: number = origin.x + along * direction.x

	return x >= WALL_LEFT and x <= WALL_RIGHT
end

-- Counts each ray of a list into a multiset by its bits
local function count(into: { [string]: number }, rays: { any })
	for _, ray: any in rays do
		local key: string = string.pack(
			RAY_FORMAT,
			ray.origin.x,
			ray.origin.y,
			ray.origin.z,
			ray.direction.x,
			ray.direction.y,
			ray.direction.z
		)
		into[key] = (into[key] or 0) + 1
	end
end

-- The scene's run in process, or on that many workers
local function run(workers: number?): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	harness.wall = wall

	local pool: any = override.made
	if workers and not pool then
		error("Anti-ESP made no pool with workers set")
	elseif pool then
		pool.wall = wall
	end

	local viewers: { any } = {}
	for index: number, at: vector in VIEWERS do
		local _, viewer: any = harness:player(`Viewer{index}`, at)
		viewers[index] = viewer
	end

	local targets: { number } = {}
	for index: number, target: Target in TARGETS do
		targets[index] = harness:body(target.kind, target.at)
	end

	local function ask(): { boolean }
		local verdicts: { boolean } = {}
		for _, viewer: any in viewers do
			for _, target: number in targets do
				table.insert(verdicts, Harness.AntiEsp.isHidden(viewer, target))
			end
		end

		return verdicts
	end

	local result: Run = { verdicts = {}, rays = {}, workers = {}, inProcess = 0 }
	ask()

	for slice: number = 0, SLICES - 1 do
		harness:slice(slice * STEP)

		if pool then
			-- A slice packs what the next tests in process, so the last slice's batch is a test the run never reaches
			if slice < SLICES - 1 then
				count(result.rays, pool.rays)
			end

			table.clear(pool.rays)
			result.inProcess += #harness.rays
		else
			count(result.rays, harness.rays)
		end

		table.insert(result.verdicts, ask())
	end

	if pool then
		for _, sent: any in pool.sends do
			result.workers[sent.worker] = true
		end
	end

	return result
end

return function (): (boolean, string | nil)
	local serial: Run = run(nil)

	-- The scene holds both verdicts, so an answer that loses either shows
	local last: { boolean } = serial.verdicts[SLICES]
	if not table.find(last, true) or not table.find(last, false) then
		return false, "The scene in process left every pair hidden or every pair shown"
	end

	for _, workers: number in { 2, 3 } do
		local pooled: Run = run(workers)

		if pooled.inProcess ~= 0 then
			return false, `On {workers} workers, {pooled.inProcess} rays were cast in process`
		end

		for worker: number = 1, workers do
			if not pooled.workers[worker] then
				return false, `On {workers} workers, worker {worker} was never sent a batch`
			end
		end

		for slice: number = 2, SLICES do
			for pair: number, hidden: boolean in serial.verdicts[slice] do
				if pooled.verdicts[slice][pair] ~= hidden then
					return false,
						`On {workers} workers, pair {pair}'s verdict at slice {slice} was not the in-process one`
				end
			end
		end

		for key: string, times: number in serial.rays do
			if pooled.rays[key] ~= times then
				return false,
					`On {workers} workers, a ray cast in process was cast {pooled.rays[key] or 0} times, not {times}`
			end
		end

		for key: string, times: number in pooled.rays do
			if serial.rays[key] == nil then
				return false, `On {workers} workers, a ray never cast in process was cast {times} times`
			end
		end
	end

	return true, nil
end
