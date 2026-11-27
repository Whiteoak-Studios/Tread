--[[
    A visible pair's open recheck whose batch misses its slice is given up
    there and retested at once, behind the wall that closed since, so its hold
    runs from its first test and it is hidden at the same slice as in process
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKER: number = 1
local STEP: number = 1 / 64
local SLICES: number = 160 -- Past the 1 s hold after the first test and its 2 Hz rechecks
local RELEASE: number = 2 -- Slices after its send the held batch comes back, a slice after it was given up
local TARGET: vector = vector.create(0, 0, -40)

-- What one run saw: the slice after which the wall closed, the first after it the pair was hidden at, and on the
-- worker whether the slice after the close tested the pair again in process
type Run = {
	closedAt: number?,
	hiddenAt: number?,
	retested: boolean,
}

local function run(workers: number?, closeAt: number?): Run
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)
	local result: Run = { closedAt = nil, hiddenAt = nil, retested = false }
	local releaseAt: number? = nil
	local tests: number = 0

	harness.wall = Harness.open
	if pool then
		pool.wall = Harness.open
	end

	AntiEsp.isHidden(viewer, target)

	for slice: number = 0, SLICES - 1 do
		if pool then
			table.clear(pool.sends)

			if releaseAt == slice then
				pool.held[WORKER] = false
			end
		end

		harness:slice(slice * STEP)

		-- The first recheck, of the pair seen at its first test, is sent with the wall still open and held back
		local settled: number = AntiEsp.counts()
		if pool and result.closedAt == nil and settled == 1 and #pool.sends == 1 then
			pool.held[WORKER] = true
			releaseAt = slice + RELEASE
			result.closedAt = slice
		elseif closeAt == slice then
			result.closedAt = slice
		end

		if result.closedAt == slice then
			harness.wall = Harness.solid
			if pool then
				pool.wall = Harness.solid
			end
		end

		-- The slice after, with its one worker out, retests the pair of the batch it gave up here
		if pool and result.closedAt == slice - 1 then
			result.retested = settled == tests + 1 and #pool.sends == 0 and #harness.rays > 0
		end

		tests = settled

		-- Asked every run, as the relay asks, and hidden only counts once the wall has closed, as the pair starts
		-- hidden until its first answer
		local hidden: boolean = AntiEsp.isHidden(viewer, target)
		if hidden and result.closedAt and slice > result.closedAt and result.hiddenAt == nil then
			result.hiddenAt = slice
		end
	end

	return result
end

return function (): (boolean, string | nil)
	local pooled: Run = run(WORKER, nil)
	if pooled.closedAt == nil then
		return false, "The worker's open recheck was never held"
	elseif not pooled.retested then
		return false, "The slice after the held batch missed its own did not test its pair again in process"
	end

	local serial: Run = run(nil, pooled.closedAt)

	if serial.hiddenAt == nil or pooled.hiddenAt == nil then
		return false, `The pair was never hidden: in process at {serial.hiddenAt}, on the worker at {pooled.hiddenAt}`
	elseif pooled.hiddenAt ~= serial.hiddenAt then
		return false,
			`With the given-up open answer the pair was hidden at slice {pooled.hiddenAt}, not {serial.hiddenAt}`
	end

	return true, nil
end
