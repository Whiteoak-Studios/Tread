--[[
    Running whole, a viewer that leaves at the place a cut walk stopped at
    is passed over when the next walk starts there, which goes on to the
    viewers after it, and a viewer that joins at that freed place is walked
    as any other
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EDGE: vector = vector.create(4, 0, 0) -- At the example's 4-stud retest, so its viewer is measured every slice
local PAST: vector = vector.create(5, 0, 0) -- Past it, so its viewer's walk triggers its group

-- Each bot viewer's one sleeper, in the order anti-ESP walks them, then the one the joining viewer asks about
local PLACES: { vector } = {
	vector.create(-30, 0, 0),
	vector.create(0, 0, 30),
	vector.create(30, 0, 30),
	vector.create(-30, 0, -30),
	vector.create(30, 0, -30),
}

local LEAVING: number = 3 -- The viewer at the place the first cut walk stops at
local JOINING: number = 5 -- The viewer that joins once it has left
local JOINED_AT: number = 1.3 -- When the joining viewer's first test runs
local WALKED_AT: number = 2 -- Past its group's 1.5 Hz rate since that test

-- Each slice's time, its late read and the sleepers it retests, from the example's 4 studs and 1.5 Hz
local STEPS: { { any } } = {
	{ 1, 4, {} }, -- The walk cut at the third viewer, after the first two
	{ 1.1, 6, { 2 } }, -- The second's sleeper, then a walk from the third's freed place: the fourth, cut at the first
	{ 1.2, math.huge, { 4 } }, -- The fourth's sleeper
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp
	local box: any = harness.shared.step.lyingBox

	AntiEsp.useWhole(true)

	local viewers: { any } = {}
	local sleepers: { number } = {}
	local heads: { vector } = {}
	local asking: { [number]: boolean } = {}

	for index: number, at: vector in PLACES do
		viewers[index] = harness:viewer(`Walker{index}`, nil)
		sleepers[index] = harness:body("Sleeper", at)
		heads[index] = vector.create(at.x, box.lift, at.z - box.length / 2)
		asking[index] = index ~= JOINING
	end

	local function ask()
		for index: number, viewer: any in viewers do
			if asking[index] then
				AntiEsp.isHidden(viewer, sleepers[index])
			end
		end
	end

	-- The sleepers a slice retested, each by its head ray, checked against the ones named
	local function retested(now: number, expected: { number }): string?
		if #harness.rays ~= #expected then
			return `The slice at {now} s cast {#harness.rays} rays, not {#expected}`
		end

		for _, sleeper: number in expected do
			if harness:endingAt(heads[sleeper]) ~= 1 then
				return `The slice at {now} s didn't retest sleeper {sleeper}`
			end
		end

		return nil
	end

	-- Each seen from where it stands, then the first stands at the retest distance and the next three past it
	ask()
	harness:slice(0)

	viewers[1].position = EDGE
	for index: number = 2, 4 do
		viewers[index].position = PAST
	end

	for index: number, step: { any } in STEPS do
		ask()
		harness:sliceOn(clock, step[1], step[2])

		local why: string? = retested(step[1], step[3])
		if why then
			return false, why
		end

		-- The viewer at the cut walk's place leaves after the first slice
		if index == 1 then
			AntiEsp.leave(viewers[LEAVING].key)
			asking[LEAVING] = false
		end
	end

	-- A viewer joins at the freed place: its pair is tested at once, and once it walks past, its walk triggers it
	asking[JOINING] = true
	ask()
	harness:sliceOn(clock, JOINED_AT)

	local why: string? = retested(JOINED_AT, { JOINING })
	if why then
		return false, why
	end

	viewers[JOINING].position = PAST
	ask()
	harness:sliceOn(clock, WALKED_AT)

	why = retested(WALKED_AT, { JOINING })
	if why then
		return false, why
	elseif AntiEsp.reason(viewers[LEAVING].key, sleepers[LEAVING]) ~= "Untested" then
		return false, "The viewer that left still held its pair"
	end

	return true, nil
end
