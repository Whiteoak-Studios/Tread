--[[
    On anti-ESP's workers a near hidden pair is packed at each tick's first
    slice, and one packed at a tick's last slice lands and is packed again
    at the next tick's first, so no tick goes untested
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local NEAR: number = 200 -- Studs from the viewer, inside the example's 250-stud near radius
local TICKS: number = 6
local SLICES: number = 3 -- Slices a tick, at 60 Heartbeats a second and the example's 20 Hz
local MOVED_BEFORE: number = 8 -- The slice, tick 2's last, before which a move makes the pair due at once

-- The slices that pack the pair: each tick's first, the move's, and tick 3's first again, where its batch lands due
local PACKED: string = "0,3,6,8,9,12,15"

local Example: any = Environment.load(EXAMPLE)
local STEP: number = 1 / (Example.shared().rates.simulation * SLICES) -- Seconds between slices

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local clock: any = Harness.clock()
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end, clock.read)

	local pool: any = override.made
	if pool == nil then
		return false, "Anti-ESP made no pool with antiEsp.workers above 0"
	end

	harness.wall = Harness.solid
	pool.wall = Harness.solid

	local AntiEsp: any = Harness.AntiEsp
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -NEAR))
	AntiEsp.isHidden(viewer, target)

	local packed: { string } = {}
	local ticks: { [number]: boolean } = {}

	for slice: number = 0, TICKS * SLICES - 1 do
		if slice == MOVED_BEFORE then
			AntiEsp.moved(target)
		end

		local tick: number = slice // SLICES
		table.clear(pool.sends)
		harness:sliceOn(clock, slice * STEP, nil, tick)

		if #harness.rays > 0 then
			return false, `Slice {slice} cast {#harness.rays} rays in process with a worker free`
		end

		local sent: number = 0
		for _, send: any in pool.sends do
			sent += send.pairs
		end

		if sent > 0 then
			table.insert(packed, tostring(slice))
			ticks[tick] = true
		end

		if not AntiEsp.isHidden(viewer, target) then
			return false, `The pair was not hidden after slice {slice}`
		end
	end

	if table.concat(packed, ",") ~= PACKED then
		return false, `The pair was packed at slices {table.concat(packed, ",")}, not {PACKED}`
	end

	for tick: number = 0, TICKS - 1 do
		if not ticks[tick] then
			return false, `No slice of tick {tick} packed the pair`
		end
	end

	return true, nil
end
