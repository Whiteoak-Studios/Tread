--[[
    A hidden pair's recheck due between two slices is packed at the first
    of them, one slice early, and lands at the second, where in process it
    is tested, every 0.1 s, its first test in the server's first slice
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local STEP: number = 1 / 64 -- Seconds between slices, exact in binary, which 0.1 s is no multiple of
local SLICES: number = 40
local TARGET: vector = vector.create(0, 0, -300) -- Past the example's 250-stud near radius, so on its 10 Hz recheck

type Run = {
	cast: { number }, -- The slices that cast the pair's rays, counted from 0
	settled: { number }, -- The slices its tests settled in
	interval: number, -- The example's hidden recheck, in seconds
}

-- The pair's slices, in process or on one worker
local function run(workers: number?): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	harness.wall = Harness.solid

	local pool: any = override.made
	if pool then
		pool.wall = Harness.solid
	end

	local AntiEsp: any = Harness.AntiEsp
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)
	local result: Run = { cast = {}, settled = {}, interval = 1 / harness.server.antiEsp.hiddenRate }
	local tests: number = 0

	-- Asked before the server's first slice, which has no slice before it to lead by, so the first test's answer
	-- settles on the clock it was aimed at, as in process
	AntiEsp.isHidden(viewer, target)

	for slice: number = 0, SLICES - 1 do
		harness:slice(slice * STEP)

		local rays: { any } = harness.rays
		if pool then
			rays = table.clone(pool.rays)
			table.clear(pool.rays)
		end

		if #rays > 0 then
			table.insert(result.cast, slice)
		end

		local settled: number = AntiEsp.counts()
		if settled > tests then
			table.insert(result.settled, slice)
			tests = settled
		end

		AntiEsp.isHidden(viewer, target)
	end

	return result
end

return function (): (boolean, string | nil)
	local serial: Run = run(nil)
	local pooled: Run = run(1)

	if #serial.settled < 3 or #pooled.settled ~= #serial.settled then
		return false, `The worker settled {#pooled.settled} tests where in process {#serial.settled} settled`
	end

	for index: number, slice: number in pooled.settled do
		-- Each verdict lands a slice after its rays were packed
		if pooled.cast[index] ~= slice - 1 then
			return false, `The worker's test {index} settled at slice {slice}, not the one after its rays went`
		elseif index == 1 then
			continue
		end

		-- Each recheck lands at the slice it is tested in process, the interval after the last as there
		if slice ~= serial.settled[index] then
			return false, `The worker's test {index} landed at slice {slice}, in process at {serial.settled[index]}`
		end

		-- Which is where the last one settled, at the reach it was packed with
		local gap: number = (slice - serial.settled[index - 1]) * STEP
		if gap < pooled.interval or gap >= pooled.interval + STEP then
			return false, `The worker's test {index} came {gap} s after the slice the last one settled on`
		end
	end

	return true, nil
end
