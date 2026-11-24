--[[
    AntiEsp.rays gives the rays cast since its last call: in process each
    slice's own, and on workers each batch's as it lands, from the open
    ray's place or every ray when none was open, through to the last batch
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64
local SLICES: number = 12
local OPEN_BELOW: number = 3.5 -- Studs: a ray ending lower is open, so a standing pair's torso ray opens after three
local CLOSED_AFTER: number = 6 -- The slice from which every ray is blocked, so some pairs cast every ray

type Target = { kind: string, at: vector }

local TARGETS: { Target } = {
	{ kind = "Player", at = vector.create(0, 0, -40) },
	{ kind = "Player", at = vector.create(30, 0, -60) },
	{ kind = "Sleeper", at = vector.create(-30, 0, -20) },
	{ kind = "Body", at = vector.create(15, 0, 25) },
}

-- Each slice's rays as counted, and as cast in process and by the workers
type Run = {
	counted: { number },
	cast: { number },
	sent: { number },
}

local function run(workers: number?): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local closed: boolean = false

	local function wall(origin: vector, direction: vector): boolean
		return closed or (origin + direction).y >= OPEN_BELOW
	end

	harness.wall = wall
	if pool then
		pool.wall = wall
	end

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for _, target: Target in TARGETS do
		table.insert(targets, harness:body(target.kind, target.at))
	end

	local result: Run = { counted = {}, cast = {}, sent = {} }
	AntiEsp.rays()

	-- Every pair due each slice by the viewer's own move, and one slice more after the last so its batch lands
	for slice: number = 0, SLICES do
		closed = slice >= CLOSED_AFTER

		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end

		if slice < SLICES then
			AntiEsp.moved(own)
		end

		harness:slice(slice * STEP)

		table.insert(result.counted, AntiEsp.rays())
		table.insert(result.cast, #harness.rays)
		if pool then
			table.insert(result.sent, #pool.rays)
			table.clear(pool.rays)
		end
	end

	return result
end

local function sum(values: { number }): number
	local total: number = 0
	for _, value: number in values do
		total += value
	end

	return total
end

return function (): (boolean, string | nil)
	local serial: Run = run(nil)

	for index: number, counted: number in serial.counted do
		if counted ~= serial.cast[index] then
			return false, `In process slice {index - 1} counted {counted} rays and cast {serial.cast[index]}`
		end
	end

	local pooled: Run = run(WORKERS)
	if sum(pooled.cast) ~= 0 then
		return false, `On workers {sum(pooled.cast)} rays were cast in process`
	elseif pooled.counted[1] ~= 0 then
		return false, `The first slice counted {pooled.counted[1]} rays before any batch landed`
	end

	-- Each slice counts the rays of the batches the slice before sent
	for index: number = 2, #pooled.counted do
		if pooled.counted[index] ~= pooled.sent[index - 1] then
			return false,
				`Slice {index - 1} counted {pooled.counted[index]} rays, its batches cast {pooled.sent[index - 1]}`
		end
	end

	-- The walls opened some pairs part way and blocked every ray of others, so a count that skips either shows
	if sum(pooled.counted) ~= sum(pooled.sent) or sum(serial.cast) == 0 then
		return false, `On workers {sum(pooled.counted)} rays were counted of the {sum(pooled.sent)} cast`
	end

	return true, nil
end
