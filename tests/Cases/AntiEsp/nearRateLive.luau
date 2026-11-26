--[[
    AntiEsp.setNearRate moves a near hidden pair's recheck from its next
    test, never sooner and never another schedule's, the getter gives the
    rate set exactly, and a refused rate leaves the rate as it was
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ANTI_ESP: string = "src/Server/AntiEsp.luau"
local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local RAISED: number = 60 -- Hz, the near rate set in place of the example's 30
local EXACT: number = 49 -- A rate its interval doesn't give back, as 1 / (1 / 49) is not 49
local NEAR: number = 200 -- Studs from the viewer, inside the example's 250-stud near radius
local NEWER: number = 150 -- Another near target's, whose first test comes after the change
local FAR: number = 300
local EARLY: number = 0.9 -- The share of an interval at which a slice comes before the recheck is due
local HALF: number = 0.5

-- Rates the setter refuses, each in a row of its own so nil can sit in one
local NOT_RATES: { { any } } = { { 0 }, { -1 }, { 0 / 0 }, { math.huge }, { -math.huge }, { "60" }, {} }

-- A pair the change must leave on its own schedule: how far its target stands, whether every ray is blocked, and
-- the interval its recheck keeps
type Trial = { distance: number, blocked: boolean, interval: (server: any) -> number }

local TRIALS: { Trial } = {
	{
		distance = FAR,
		blocked = true,
		interval = function (server: any): number
			return 1 / server.antiEsp.hiddenRate
		end,
	},
	{
		distance = NEAR,
		blocked = false,
		interval = function (server: any): number
			return 1 / server.antiEsp.visibleRate
		end,
	},
}

-- Whether the slice just run tested the target standing at z on the line ahead of the viewer, from where its rays end
local function tested(harness: any, z: number): boolean
	for _, ray: any in harness.rays do
		if ray.to.z == z then
			return true
		end
	end

	return false
end

--[[
    A near pair queued at the old rate and one first tested after the
    change, whose recheck at the new rate would come before the queue's
    last, through slices at times worked out from both rates
--]]

local function queued(): string?
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	harness.wall = Harness.solid

	local AntiEsp: any = Harness.AntiEsp
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local near: number = harness:body("Player", vector.create(0, 0, -NEAR))
	local newer: number = harness:body("Player", vector.create(0, 0, -NEWER))
	local old: number = 1 / harness.server.antiEsp.nearRate
	local new: number = 1 / RAISED

	-- Each slice's time and whether it tests the pair queued at the old rate and the one made after the change, each
	-- time the module's own sum, so a recheck lands on its slice's time to the bit
	local slices: { { number | boolean } } = {
		{ 0, true, false },
		{ new * HALF, false, true }, -- The newer pair's first test, its recheck at new * HALF + new held behind old
		{ old * EARLY, false, false }, -- Past where either would be due at the new rate from its test before
		{ 0 + old, true, true },
		{ old + new * EARLY, false, false },
		{ old + new, true, true },
	}

	AntiEsp.isHidden(viewer, near)

	for index: number, slice: { number | boolean } in slices do
		local now: number = slice[1] :: number
		local wantNear: boolean = slice[2] :: boolean
		local wantNewer: boolean = slice[3] :: boolean

		harness:sliceOn(clock, now)

		if tested(harness, -NEAR) ~= wantNear then
			local went: string = wantNear and "went untested" or "was tested"
			return `The pair queued at the old rate {went} at {now} s`
		elseif tested(harness, -NEWER) ~= wantNewer then
			local went: string = wantNewer and "went untested" or "was tested"
			return `The pair first tested after the change {went} at {now} s`
		end

		if index == 1 then
			AntiEsp.setNearRate(RAISED)

			if AntiEsp.nearRate() ~= RAISED then
				return `AntiEsp.nearRate gave {AntiEsp.nearRate()} after AntiEsp.setNearRate({RAISED})`
			end
		end

		-- Each pair asked every slice, the newer from the change on, so none is dropped and none fails open
		if not AntiEsp.isHidden(viewer, near) or not AntiEsp.isHidden(viewer, newer) then
			return `A near pair behind the walls was sent after the slice at {now} s`
		end
	end

	return nil
end

-- A far hidden or visible pair through the change, made after its first test, which must keep its own interval
local function kept(trial: Trial): string?
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	if trial.blocked then
		harness.wall = Harness.solid
	end

	local AntiEsp: any = Harness.AntiEsp
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -trial.distance))
	AntiEsp.isHidden(viewer, target)

	local interval: number = trial.interval(harness.server)
	local slices: { { number | boolean } } = {
		{ 0, true },
		{ interval * EARLY, false },
		{ 0 + interval, true },
		{ interval + interval * EARLY, false },
		{ interval + interval, true },
	}

	local kind: string = trial.blocked and "hidden" or "visible"
	for index: number, slice: { number | boolean } in slices do
		local now: number = slice[1] :: number
		local due: boolean = slice[2] :: boolean

		harness:sliceOn(clock, now)

		if (#harness.rays > 0) ~= due then
			local wanted: string = due and "" or "not "
			local cast: string = `A {kind} pair {trial.distance} studs apart cast {#harness.rays} rays at {now} s`
			return `{cast}, where a test was {wanted}due`
		end

		if index == 1 then
			AntiEsp.setNearRate(RAISED)
		end

		if AntiEsp.isHidden(viewer, target) ~= trial.blocked then
			return `A pair {trial.distance} studs apart was not {kind} after the slice at {now} s`
		end
	end

	return nil
end

-- A call before start and every rate but a finite number above 0 refused, each leaving the rate as it was
local function refusals(): string?
	local Fresh: any = Environment.load(ANTI_ESP)
	local before: number = Fresh.nearRate()

	local refused: boolean, why: string = Refuses("setNearRate ran before AntiEsp.start", Fresh.setNearRate, RAISED)
	if not refused then
		return `AntiEsp.setNearRate before start went another way: {why}`
	elseif Fresh.nearRate() ~= before then
		return `A refused AntiEsp.setNearRate before start left the rate {Fresh.nearRate()}, not {before}`
	end

	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Harness.clock().read)
	local AntiEsp: any = Harness.AntiEsp
	local configured: number = harness.server.antiEsp.nearRate

	if AntiEsp.nearRate() ~= configured then
		return `AntiEsp.nearRate gave {AntiEsp.nearRate()} after start, not the configured {configured}`
	end

	AntiEsp.setNearRate(EXACT)
	if AntiEsp.nearRate() ~= EXACT then
		return `AntiEsp.nearRate gave {AntiEsp.nearRate()} after AntiEsp.setNearRate({EXACT})`
	end

	for _, row: { any } in NOT_RATES do
		local value: any = row[1]

		refused, why = Refuses("setNearRate takes a rate in Hz", AntiEsp.setNearRate, value)
		if not refused then
			return `AntiEsp.setNearRate({value}) went another way: {why}`
		elseif AntiEsp.nearRate() ~= EXACT then
			return `A refused AntiEsp.setNearRate({value}) left the rate {AntiEsp.nearRate()}, not {EXACT}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local failure: string? = queued()
	if failure ~= nil then
		return false, failure
	end

	for _, trial: Trial in TRIALS do
		failure = kept(trial)
		if failure ~= nil then
			return false, failure
		end
	end

	failure = refusals()
	if failure ~= nil then
		return false, failure
	end

	return true, nil
end
