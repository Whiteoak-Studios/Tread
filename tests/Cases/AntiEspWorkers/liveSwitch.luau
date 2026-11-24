--[[
    Flipping the workers off mid-run lands the batches out at the next slice,
    their rays counted, and casts in process from then; flipping them on
    packs again; the still scene's verdicts stay the in-process ones throughout
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64
local SLICES: number = 72 -- Past a visible pair's 2 Hz recheck in each stretch
local OFF: number = 20 -- The slice the switch goes off before
local ON: number = 44 -- And on again

-- A wall across z = -50 from x = -200 to 10.5, as tall as any ray
local WALL_Z: number = -50
local WALL_LEFT: number = -200
local WALL_RIGHT: number = 10.5

local VIEWERS: { vector } = { vector.create(0, 0, 0), vector.create(60, 0, 0) }

type Target = { kind: string, at: vector }

local TARGETS: { Target } = {
	{ kind = "Player", at = vector.create(-20, 0, -100) },
	{ kind = "Player", at = vector.create(20, 0, -100) }, -- Seen from the origin past the wall's end by a side ray
	{ kind = "Player", at = vector.create(100, 0, -100) },
	{ kind = "Sleeper", at = vector.create(-40, 0, -80) },
}

-- Each slice's verdicts, and with workers what each slice sent, cast in process and counted
type Run = {
	verdicts: { { boolean } },
	sent: { number }, -- The pairs a slice sent
	inProcess: { number }, -- The rays a slice cast in process
	workerRays: { number }, -- The rays the workers cast for what a slice sent
	counted: { number }, -- The rays AntiEsp.rays gave after a slice
}

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

local function run(workers: number?): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	harness.wall = wall
	if pool then
		pool.wall = wall
	end

	local viewers: { any } = {}
	local owns: { number } = {}
	for index: number, at: vector in VIEWERS do
		local slot: number, viewer: any = harness:player(`Viewer{index}`, at)
		viewers[index] = viewer
		owns[index] = slot
	end

	local targets: { number } = {}
	for index: number, target: Target in TARGETS do
		targets[index] = harness:body(target.kind, target.at)
	end

	local function ask(): { boolean }
		local verdicts: { boolean } = {}
		for _, viewer: any in viewers do
			for _, target: number in targets do
				table.insert(verdicts, AntiEsp.isHidden(viewer, target))
			end
		end

		return verdicts
	end

	local result: Run = { verdicts = {}, sent = {}, inProcess = {}, workerRays = {}, counted = {} }
	ask()

	for slice: number = 0, SLICES - 1 do
		if pool and slice == OFF then
			AntiEsp.useWorkers(false)
		elseif pool and slice == ON then
			AntiEsp.useWorkers(true)
		end

		-- Every pair due at the slice before the switch goes off and at the one it comes on, on both runs alike
		if slice == OFF - 1 or slice == ON then
			for _, slot: number in owns do
				AntiEsp.moved(slot)
			end
		end

		harness:slice(slice * STEP)

		local sent: number = 0
		if pool then
			for _, send: any in pool.sends do
				sent += send.pairs
			end

			table.clear(pool.sends)
			table.insert(result.workerRays, #pool.rays)
			table.clear(pool.rays)
		end

		table.insert(result.sent, sent)
		table.insert(result.inProcess, #harness.rays)
		table.insert(result.counted, AntiEsp.rays())
		table.insert(result.verdicts, ask())
	end

	return result
end

return function (): (boolean, string | nil)
	local serial: Run = run(nil)
	local pooled: Run = run(WORKERS)

	-- Slices count from 0, the lists from 1
	for slice: number = 0, SLICES - 1 do
		local at: number = slice + 1
		local on: boolean = slice < OFF or slice >= ON

		if on and pooled.inProcess[at] ~= 0 then
			return false, `With the switch on, slice {slice} cast {pooled.inProcess[at]} rays in process`
		elseif not on and pooled.sent[at] ~= 0 then
			return false, `With the switch off, slice {slice} sent {pooled.sent[at]} pairs`
		elseif slice >= 1 and pooled.counted[at] ~= pooled.workerRays[at - 1] + pooled.inProcess[at] then
			return false, `Slice {slice} counted {pooled.counted[at]} rays, not those landed and cast in process`
		end
	end

	-- The batch out as the switch went off lands at its first slice off, and that slice's rays count it
	if pooled.sent[OFF] == 0 or pooled.workerRays[OFF] == 0 then
		return false, "No batch was out as the switch went off"
	elseif pooled.sent[ON + 1] == 0 then
		return false, "The slice the switch came back on sent nothing"
	end

	for slice: number = 2, SLICES do
		for pair: number, hidden: boolean in serial.verdicts[slice] do
			if pooled.verdicts[slice][pair] ~= hidden then
				return false, `Pair {pair}'s verdict after slice {slice - 1} was not the in-process one`
			end
		end
	end

	return true, nil
end
