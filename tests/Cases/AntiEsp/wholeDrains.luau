--[[
    Running whole, each drain reads the clock before every 16 entries and
    stops at the deadline, testing nothing; the next drains start at a queue
    cut before its first entry, or at the one after a queue cut partway, and
    a long queue goes on from the entry it stopped at
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a player's feet that every ray to it ends within
local HIDDEN: number = 17 -- Hidden players past the near radius, one more than a drain takes between two reads
local NEAREST: number = 300 -- Studs to the first of them, past the example's 250-stud near radius
local SPACING: number = 10 -- Studs between them, so they wait on the hidden queue in that order
local SEEN: vector = vector.create(20, 0, 0) -- The visible player
local DUE: number = 0.5 -- When the visible player's 2 Hz recheck and every hidden 10 Hz one are due
local RAYS: number = 6 -- A hidden player's rays, every one blocked

-- Each slice's late read and the players it tests, all at DUE with no ask between, so none is dropped or fails open.
-- 0 names the visible player and two numbers a run of the hidden ones
local STEPS: { { any } } = {
	{ 2, {} }, -- Cut at the hidden queue's first entry, before taking it, so that queue keeps its turn
	{ 3, {} }, -- Begun at the drains, from the hidden queue again: its first 16, cut before its 17th
	-- Begun at the tests: those 16 (reads 3 to 34), then the drains from the near queue on: the visible player at
	-- read 35, then cut at the hidden queue's 17th, which it takes nothing from
	{ 36, { 1, 16 } },
	{ math.huge, { 0 } }, -- Begun at the tests: the visible player, then the drains from the hidden queue: the 17th
	{ math.huge, { 17, 17 } }, -- The 17th
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	AntiEsp.useWhole(true)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local seen: number = harness:body("Player", SEEN)
	local hidden: { number } = {}
	local walled: { [number]: boolean } = {}

	for index: number = 1, HIDDEN do
		local at: vector = vector.create(0, 0, -(NEAREST + SPACING * (index - 1)))
		hidden[index] = harness:body("Player", at)
		walled[at.z] = true
	end

	-- A ray is blocked when it ends at a hidden player, each placed on its own Z
	harness.wall = function (origin: vector, direction: vector): boolean
		return walled[math.round((origin + direction).z)] == true
	end

	local function ask()
		AntiEsp.isHidden(viewer, seen)
		for _, slot: number in hidden do
			AntiEsp.isHidden(viewer, slot)
		end
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

	-- Every pair tested at 0 s, so the visible one waits on the visible queue and the hidden ones on the hidden one
	ask()
	harness:slice(0)
	ask()

	for index: number, step: { any } in STEPS do
		local range: { number } = step[2]

		harness:sliceOn(clock, DUE, step[1])

		local expected: number = 0
		if range[1] == 0 then
			expected = 1

			if raysAt(seen) ~= 1 then
				return false, `Slice {index} didn't test the visible player`
			end
		elseif range[1] ~= nil then
			for at: number = range[1], range[2] do
				if raysAt(hidden[at]) ~= RAYS then
					return false, `Slice {index} cast {raysAt(hidden[at])} rays at hidden player {at}, not {RAYS}`
				end
			end

			expected = RAYS * (range[2] - range[1] + 1)
		end

		if #harness.rays ~= expected then
			return false, `Slice {index} cast {#harness.rays} rays, not {expected}`
		end
	end

	if AntiEsp.cuts() ~= 3 then
		return false, `Three slices cut in their drains counted {AntiEsp.cuts()} cuts`
	end

	return true, nil
end
