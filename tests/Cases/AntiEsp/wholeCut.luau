--[[
    Running whole on a clock that stays past the deadline once it gets
    there, as a live one does, a slice cut in its drains casts no ray, and
    the pairs it let wait are tested in the next slice, which begins at its
    tests, before its own drains let the rest wait for the slice after
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a player's feet that every ray to it ends within
local WALLED: vector = vector.create(0, 0, -300) -- Past the example's 250-stud near radius, so on the 10 Hz queue
local SEEN: vector = vector.create(20, 0, 0) -- Rays open, so on the 2 Hz queue
local DUE: number = 0.5 -- When both rechecks are due
local LATE_READ: number = 3 -- The deadline, the hidden queue's first entry, then the visible queue's, found passed
local HIDDEN_RAYS: number = 6

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	AntiEsp.useWhole(true)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local walled: number = harness:body("Player", WALLED)
	local seen: number = harness:body("Player", SEEN)

	harness.wall = function (origin: vector, direction: vector): boolean
		return math.round((origin + direction).z) == WALLED.z
	end

	-- How many of a slice's rays end at a player
	local function raysAt(slot: number): number
		local feet: vector = harness.states[slot].position
		local count: number = 0

		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet
			if math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				count += 1
			end
		end

		return count
	end

	-- Both tested at 0 s, then asked about once more, with no ask between the slices after
	AntiEsp.isHidden(viewer, walled)
	AntiEsp.isHidden(viewer, seen)
	harness:slice(0)
	AntiEsp.isHidden(viewer, walled)
	AntiEsp.isHidden(viewer, seen)

	-- The cut slice: the hidden player's recheck taken from its queue, the visible one's left at its queue's front
	harness:sliceOn(clock, DUE, LATE_READ)
	if #harness.rays ~= 0 then
		return false, `The cut slice cast {#harness.rays} rays past its deadline`
	end

	-- Each slice after: the hidden player tested first, the visible one drained after it and tested next
	for index: number, expected: { number } in { { HIDDEN_RAYS, 0 }, { 0, 1 } } do
		harness:sliceOn(clock, DUE)

		if raysAt(walled) ~= expected[1] or raysAt(seen) ~= expected[2] then
			local counts: string = `{raysAt(walled)} and {raysAt(seen)}`
			return false, `Slice {index} after the cut cast {counts} rays at the hidden and visible players`
		end
	end

	if AntiEsp.cuts() ~= 1 then
		return false, `One cut slice counted {AntiEsp.cuts()} cuts`
	end

	return true, nil
end
