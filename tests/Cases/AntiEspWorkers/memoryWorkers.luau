--[[
    On workers, memory gives the verdicts the workers give without it at
    every slice and the in-process ones over a still stretch; a kept pair is
    never packed, a box a worker sends back settles the next rays here, and
    only a packed pair's first ray asks what it met, never with memory off
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 60
local SLICES: number = 72 -- Past a visible pair's 2 Hz recheck in each stretch
local SHIFT_AT: number = 30 -- The slice before which the walled target steps across, still behind its wall
local REMOVE_AT: number = 50 -- And the one before which the wall goes
local SHIFT: vector = vector.create(0.5, 0, 0)
local SLICE: number = 60 -- Seconds a slice may take, so no run's tests run out on a loaded machine
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

-- One viewer, and targets behind the wall, in the open and off to the side
local TARGETS: { vector } = { vector.create(0, 0, -40), vector.create(0, 0, 40), vector.create(60, 0, 10) }
local WALLED: number = 1 -- The target that steps and whose wall goes

-- Each slice's verdicts and what it packed, cast, kept and settled by box, and the occluder's calls in the run
type Run = {
	verdicts: { { boolean } },
	sent: { number },
	inProcess: { number },
	workerRays: { number },
	kept: { number },
	boxRays: { number },
	asked: number, -- The server's own
	workerAsked: number,
}

local function run(workers: number?, remember: boolean): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useMemory(remember)

	local folder: any = harness.server.antiEsp.include[1]
	local wall: any = roblox.Instance.new("Part")
	wall.Size = roblox.Vector3.new(30, 12, 1)
	wall.CFrame = roblox.CFrame.new(0, 3, -20)
	wall.Parent = folder

	harness.wall = Harness.parts(folder)
	local pool: any = override.made
	if pool then
		pool.wall = Harness.parts(folder)
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for index: number, at: vector in TARGETS do
		targets[index] = harness:body("Player", at)
	end

	local function ask(): { boolean }
		local verdicts: { boolean } = {}
		for _, target: number in targets do
			table.insert(verdicts, AntiEsp.isHidden(viewer, target))
		end

		return verdicts
	end

	local result: Run = {
		verdicts = {},
		sent = {},
		inProcess = {},
		workerRays = {},
		kept = {},
		boxRays = {},
		asked = 0,
		workerAsked = 0,
	}
	ask()

	for slice: number = 0, SLICES - 1 do
		if slice == SHIFT_AT then
			-- Due at once, as a teleport's landing makes it, so this slice tests it on every run
			local walled: number = targets[WALLED]
			harness:move(walled, harness.states[walled].position + SHIFT)
			AntiEsp.moved(walled)
		elseif slice == REMOVE_AT then
			folder.DescendantRemoving:Fire(wall)
			wall.Parent = nil
		end

		harness:slice(slice * STEP, SLICE)

		local sent: number = 0
		if pool then
			for _, send: any in pool.sends do
				sent += send.pairs
			end

			table.clear(pool.sends)
			table.insert(result.workerRays, #pool.rays)
			table.clear(pool.rays)
		end

		local kept: number, boxRays: number = harness:remembered()
		table.insert(result.sent, sent)
		table.insert(result.inProcess, #harness.rays)
		table.insert(result.kept, kept)
		table.insert(result.boxRays, boxRays)
		table.insert(result.verdicts, ask())
	end

	result.asked = harness.occluded
	if pool then
		result.workerAsked = pool.occluded
	end

	return result
end

-- The first slice from a list's start whose verdicts differ between two runs, nil when none does
local function differing(one: Run, other: Run, from: number, to: number): number?
	for at: number = from, to do
		for pair: number, hidden: boolean in one.verdicts[at] do
			if other.verdicts[at][pair] ~= hidden then
				return at
			end
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS
	local serial: Run = run(nil, OFF)
	local serialKept: Run = run(nil, ON)
	local pooled: Run = run(WORKERS, OFF)
	local pooledKept: Run = run(WORKERS, ON)

	-- Lists count from 1, slices from 0
	local at: number? = differing(pooled, pooledKept, 1, SLICES)
	if at then
		return false, `On workers, memory's verdicts after slice {at - 1} were not the ones without it`
	end

	at = differing(serial, serialKept, 1, SLICES)
	if at then
		return false, `In process, memory's verdicts after slice {at - 1} were not the ones without it`
	end

	-- Over the still stretch, one slice in for the first batch to land, the workers' verdicts are the in-process ones
	at = differing(serialKept, pooledKept, 2, SHIFT_AT)
	if at then
		return false, `With memory on, the workers' verdicts after still slice {at - 1} were not the in-process ones`
	end

	-- No ray asks what it met with memory off, here or on a worker, and with it on each packed pair's first ray alone does
	local packed: number = 0
	for _, sent: number in pooledKept.sent do
		packed += sent
	end

	if serial.asked ~= 0 or pooled.asked ~= 0 or pooled.workerAsked ~= 0 then
		local asked: string =
			`{serial.asked} times in process, {pooled.asked} beside workers and {pooled.workerAsked} on them`
		return false, `With memory off the occluder was asked {asked}`
	elseif pooledKept.workerAsked ~= packed then
		return false,
			`With memory on the workers asked the occluder {pooledKept.workerAsked} times for {packed} pairs packed`
	end

	-- Past each pair's first test, every pair the plain workers pack is kept with memory and none of them is packed,
	-- each kept answer counted where it lands, beside the batches, at the next slice. The walled pair is tested at
	-- each tick's first slice, so none of its answers is out at the last still slice, the third of its tick
	local kept: number = 0
	for slice: number = 2, SHIFT_AT do
		local landed: number = pooledKept.kept[slice + 1]

		if pooledKept.sent[slice] + landed ~= pooled.sent[slice] then
			local counts: string = `{pooledKept.sent[slice]} pairs packed and {landed} kept`
			return false, `Still slice {slice - 1} gave {counts}, not the {pooled.sent[slice]} packed without memory`
		elseif pooledKept.inProcess[slice] ~= 0 then
			return false, `Still slice {slice - 1} cast {pooledKept.inProcess[slice]} rays in process`
		end

		kept += landed
	end

	if kept == 0 then
		return false, "No still slice kept an answer on the workers"
	end

	-- The walled pair's first test was packed and blocked on a worker, which sent its wall's box back
	if pooledKept.workerRays[1] < playerRays then
		return false, `The first batch cast {pooledKept.workerRays[1]} rays, not the walled pair's {playerRays}`
	end

	-- Once it stepped across, that box settled its every ray here, so the slice packed nothing for it
	local shifted: number = SHIFT_AT + 1
	if pooledKept.boxRays[shifted] ~= playerRays or pooledKept.sent[shifted] ~= pooled.sent[shifted] - 1 then
		local counts: string = `{pooledKept.boxRays[shifted]} box rays and {pooledKept.sent[shifted]} pairs packed`
		return false, `The walled pair's test after it stepped across gave {counts}`
	elseif pooledKept.workerRays[shifted] ~= 0 or pooledKept.inProcess[shifted] ~= 0 then
		return false, "The walled pair's test after it stepped across cast an engine ray"
	end

	return true, nil
end
