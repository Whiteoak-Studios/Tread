--[[
    A near hidden pair whose sight line opens at a tick is first asked as
    visible at that tick in process, split or not, and on workers with the
    split, and a tick later on workers without it, whose answer lands late
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local NEAR: number = 200 -- Studs from the viewer, inside the example's 250-stud near radius
local OPENS: number = 5 -- The tick whose step opens the sight line, odd, so tests every other slice miss its first slice
local TICKS: number = 8
local SLICES: number = 3 -- Slices a tick, at 60 Heartbeats a second and the example's 20 Hz

-- The slice of its tick after which the relay asks: with the split, its dispatch comes in the tick's second frame, after
-- that frame's slice, and without it in the tick's own Heartbeat, after that one's
local SPLIT_ASK: number = 2
local ASK: number = 1

local Example: any = Environment.load(EXAMPLE)
local STEP: number = 1 / (Example.shared().rates.simulation * SLICES) -- Seconds between slices

-- One path: on workers or not, the slice of its tick the relay asks after, and the tick it first finds the pair visible
type Path = { name: string, workers: number?, ask: number, visible: number }

local PATHS: { Path } = {
	{ name = "in process with the split", workers = nil, ask = SPLIT_ASK, visible = OPENS },
	{ name = "in process without the split", workers = nil, ask = ASK, visible = OPENS },
	{ name = "on workers with the split", workers = WORKERS, ask = SPLIT_ASK, visible = OPENS },
	{ name = "on workers without the split", workers = WORKERS, ask = ASK, visible = OPENS + 1 },
}

-- The tick at whose ask a path first finds the pair visible, nil for none, and whether a test found it so
local function firstVisible(path: Path): (number?, boolean)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local clock: any = Harness.clock()
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = path.workers
	end, clock.read)

	local open: boolean = false
	local function wall(_: vector, _: vector): boolean
		return not open
	end

	harness.wall = wall
	local pool: any = override.made
	if pool then
		pool.wall = wall
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -NEAR))
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.isHidden(viewer, target)

	for tick: number = 0, TICKS - 1 do
		-- The tick's step has run before its first slice
		open = tick >= OPENS

		for slice: number = 1, SLICES do
			harness:sliceOn(clock, ((tick * SLICES) + slice - 1) * STEP, nil, tick)

			if slice == path.ask and not AntiEsp.isHidden(viewer, target) then
				return tick, AntiEsp.reason(viewer.key, target) == "Clear"
			end
		end
	end

	return nil, true
end

return function (): (boolean, string | nil)
	for _, path: Path in PATHS do
		local visible: number?, clear: boolean = firstVisible(path)
		if visible ~= path.visible then
			return false, `{path.name}, the pair opened at tick {OPENS} was first asked visible at {visible}`
		elseif not clear then
			return false, `{path.name}, the pair was first asked visible by a fail-open, not a test`
		end
	end

	return true, nil
end
