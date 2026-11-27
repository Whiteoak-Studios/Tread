--[[
    With antiEsp.workers left out, pairs sharing a recheck queue, a moved
    one's stale entry among them, are each tested again at the first slice
    at or past its own test's clock plus the interval, in the order queued
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local STEP: number = 1 / 64
local SLICES: number = 24 -- Through each pair's second recheck
local MOVED_AT: number = 3 -- The slice the first pair is moved just before, leaving its queued recheck stale
local DISTANCE: number = 300 -- Studs, past the example's near radius, so each pair is on the 10 Hz recheck

-- Each pair's target, out along its own axis from the viewer, and the slice after which it is first asked
type Pair = {
	place: vector,
	askedAfter: number,
}

local PAIRS: { Pair } = {
	{ place = vector.create(0, 0, -DISTANCE), askedAfter = -1 },
	{ place = vector.create(DISTANCE, 0, 0), askedAfter = 0 },
	{ place = vector.create(-DISTANCE, 0, 0), askedAfter = 1 },
}

-- How many of a slice's rays end past halfway out along a pair's axis, which only that pair's rays do
local function castTo(harness: any, place: vector): number
	local count: number = 0

	for _, ray: any in harness.rays do
		if vector.dot(ray.to, place) > DISTANCE * DISTANCE / 2 then
			count += 1
		end
	end

	return count
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	local interval: number = 1 / harness.server.antiEsp.hiddenRate
	local _, viewer: any = harness:player("Viewer", vector.zero)
	harness.wall = Harness.solid

	local targets: { number } = {}
	local nextAt: { number } = {} -- The slice each pair is next due its test at
	for index: number, pair: Pair in PAIRS do
		targets[index] = harness:body("Player", pair.place)
		nextAt[index] = pair.askedAfter + 1
	end

	-- The first slice at or past a test's clock plus the interval, with the sum the module makes
	local function dueSlice(tested: number): number
		local due: number = tested * STEP + interval
		local slice: number = tested + 1

		while slice * STEP < due do
			slice += 1
		end

		return slice
	end

	local function ask(slice: number)
		for index: number, pair: Pair in PAIRS do
			if slice >= pair.askedAfter then
				AntiEsp.isHidden(viewer, targets[index])
			end
		end
	end

	ask(-1)
	for slice: number = 0, SLICES - 1 do
		if slice == MOVED_AT then
			AntiEsp.moved(targets[1])
			nextAt[1] = slice
		end

		harness:slice(slice * STEP)

		for index: number, pair: Pair in PAIRS do
			local cast: number = castTo(harness, pair.place)
			local due: boolean = nextAt[index] == slice

			if (cast > 0) ~= due then
				return false,
					`Slice {slice} cast {cast} rays to pair {index}, where its test was due at {nextAt[index]}`
			elseif due then
				nextAt[index] = dueSlice(slice)
			end
		end

		ask(slice)
	end

	return true, nil
end
