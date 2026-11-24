--[[
    A recheck due before the last entry of its queue takes that entry's time:
    an answer from a slice after a short gap, whose reach falls behind one from
    the slice before, has its recheck packed at that one's slice, not sooner
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local FAIL_OPEN: number = 1 -- Seconds, so no pair fails open while its recheck waits behind the other's
local SHORT_PARTS: number = 8 -- How many of the short gaps between slices make one relay interval
local SLICES: number = 48
local EARLY: vector = vector.create(0, 0, -300) -- Both past the near radius, on the 10 Hz recheck
local LATER: vector = vector.create(300, 0, 0)

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
		server.antiEsp.failOpen = FAIL_OPEN
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local relay: number = 1 / harness.shared.rates.relay
	local short: number = relay / SHORT_PARTS
	local interval: number = 1 / harness.server.antiEsp.hiddenRate
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local early: number = harness:body("Player", EARLY)
	local later: number = harness:body("Player", LATER)
	pool.wall = Harness.solid

	-- A relay interval's gap before the early pair's first test, so its answer reaches a whole interval past its
	-- slice, then short gaps, so the later pair's, packed at the next slice, reaches only a short gap past its own
	local function clockOf(slice: number): number
		if slice == 0 then
			return 0
		end

		return relay + (slice - 1) * short
	end

	local earlyDue: number = clockOf(1) + relay + interval
	local laterDue: number = clockOf(2) + short + interval
	if laterDue >= earlyDue - short then
		return false, "The case's clocks no longer put the later pair's recheck a slice or more before the early one's"
	end

	-- The early pair asked after the first slice and the later one after the second, then both every run
	local asking: { number } = {}
	local function ask()
		for _, target: number in asking do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- Each slice at which a ray was cast toward each pair
	local earlyPacks: { number } = {}
	local laterPacks: { number } = {}

	for slice: number = 0, SLICES - 1 do
		table.clear(pool.rays)
		harness:slice(clockOf(slice))

		-- Rays to the early pair end far along -Z, and the later pair's far along +X
		local aimedEarly: boolean = false
		local aimedLater: boolean = false
		for _, ray: any in pool.rays do
			aimedEarly = aimedEarly or ray.to.z < EARLY.z / 2
			aimedLater = aimedLater or ray.to.x > LATER.x / 2
		end

		if aimedEarly then
			table.insert(earlyPacks, slice)
		end

		if aimedLater then
			table.insert(laterPacks, slice)
		end

		if slice == 0 then
			table.insert(asking, early)
		elseif slice == 1 then
			table.insert(asking, later)
		end

		ask()
	end

	if earlyPacks[1] ~= 1 or laterPacks[1] ~= 2 then
		return false, `The first tests were packed at slices {earlyPacks[1]} and {laterPacks[1]}, not 1 and 2`
	elseif earlyPacks[2] == nil or laterPacks[2] == nil then
		return false, `The rechecks were packed at slices {earlyPacks[2]} and {laterPacks[2]}`
	elseif laterPacks[2] ~= earlyPacks[2] then
		return false,
			`The later pair's recheck was packed at slice {laterPacks[2]}, not the early one's {earlyPacks[2]}`
	end

	return true, nil
end
