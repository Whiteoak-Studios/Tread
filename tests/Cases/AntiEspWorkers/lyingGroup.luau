--[[
    A sleeper's pair a worker tested joins its viewer's group when its
    result lands, so a walk past the retest distance before the rate allows
    packs it again one slice before its rate passes, and none sooner
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local STEP: number = 1 / 64
local SLICES: number = 64
local WALK: number = 32 -- The slice the viewer walks past the retest distance at, before the rate allows a retest
local WALKED: vector = vector.create(10, 0, 0) -- Past the example's 4 studs

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local sleeper: number = harness:body("Sleeper", vector.create(0, 0, -50))
	pool.wall = Harness.solid

	-- Packed at slice 0, the first, which has no lead, so its result landing at slice 1 starts its group at 0
	local reach: number = 0
	local due: number = reach + 1 / harness.server.sleepers.rate
	local sent: { number } = {}

	for slice: number = 0, SLICES - 1 do
		if slice == WALK then
			harness:move(slot, WALKED, viewer)
		end

		AntiEsp.isHidden(viewer, sleeper)
		harness:slice(slice * STEP)

		if #pool.rays > 0 then
			table.insert(sent, slice)
			table.clear(pool.rays)
		end
	end

	-- The first slice whose reach, a slice ahead, passes the rate
	local expected: number = math.ceil(due / STEP) - 1
	if sent[1] ~= 0 or sent[2] ~= expected or #sent ~= 2 then
		return false, `The sleeper's pair was packed at slices {table.concat(sent, ", ")}, not 0 and {expected}`
	elseif not AntiEsp.isHidden(viewer, sleeper) then
		return false, "The sleeper behind the wall was shown"
	end

	return true, nil
end
