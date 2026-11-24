--[[
    Running whole, the slice after a cut begins at the step after the one
    the deadline stopped partway, or at that one when the deadline came
    before its first item: timers, then walks, then drains, then tests,
    round from there; and on a clock that cuts every slice, the tests go
    first within four slices, though each earlier step has more than a
    slice's work
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local PAST: vector = vector.create(5, 0, 0) -- Past the example's 4-stud retest, where each walker stands
local CUT_AT: number = 3 -- Past every held sleeper's timer, every walker's rate and every player's recheck
local SEEN: { number } = { 0.1, 0.2, 0.3 } -- When each held sleeper is first seen, so their timers end in that order
local RETESTED: number = 0.5 -- When the held sleepers are retested walled, inside the example's 2 s hold

-- Each body's name, kind and place, whose viewer asks about it, and whether rays to it are walled from the start
-- or from the held sleepers' retest
local BODIES: { { name: string, kind: string, at: vector, by: string, walled: string? } } = {
	{ name = "Moved", kind = "Player", at = vector.create(20, 0, 0), by = "Viewer" }, -- Made due by a move
	{ name = "Far", kind = "Player", at = vector.create(0, 0, -300), by = "Viewer", walled = "start" },
	{ name = "Near", kind = "Player", at = vector.create(0, 0, -30), by = "Viewer", walled = "start" },
	{ name = "Seen", kind = "Player", at = vector.create(-20, 0, 0), by = "Viewer" },
	{ name = "Held1", kind = "Sleeper", at = vector.create(-30, 0, 30), by = "Viewer", walled = "retest" },
	{ name = "Held2", kind = "Sleeper", at = vector.create(0, 0, 40), by = "Viewer", walled = "retest" },
	{ name = "Held3", kind = "Sleeper", at = vector.create(30, 0, 40), by = "Viewer", walled = "retest" },
	{ name = "Lying1", kind = "Sleeper", at = vector.create(-40, 0, -40), by = "Walker1" },
	{ name = "Lying2", kind = "Sleeper", at = vector.create(40, 0, -40), by = "Walker2" },
	{ name = "Lying3", kind = "Sleeper", at = vector.create(60, 0, 10), by = "Walker3" },
}

-- Rays to a body: one when open, every one when walled
local RAYS: { [string]: number } = {
	Moved = 1,
	Far = 6,
	Near = 6,
	Seen = 1,
	Held1 = 3,
	Held2 = 3,
	Held3 = 3,
	Lying1 = 1,
	Lying2 = 1,
	Lying3 = 1,
}

-- One world, every item of each earlier step due at CUT_AT with no ask between the slices from there
type World = {
	harness: any,
	clock: any,
	AntiEsp: any,
	slots: { [string]: number },
}

local function build(): World
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useWhole(true)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local viewers: { [string]: any } = { Viewer = viewer }
	for index: number = 1, 3 do
		viewers[`Walker{index}`] = harness:viewer(`Walker{index}`, nil)
	end

	local slots: { [string]: number } = {}
	local walled: { [string]: boolean } = {}
	for _, body in BODIES do
		slots[body.name] = harness:body(body.kind, body.at)
		walled[body.name] = body.walled == "start"
	end

	harness.wall = function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		for _, body in BODIES do
			local offset: vector = finish - body.at
			if walled[body.name] and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				return true
			end
		end

		return false
	end

	-- Every viewer's asks, the held sleepers' up to the given one, the viewer first so it walks first
	local function ask(held: number)
		for _, body in BODIES do
			local index: number? = tonumber(string.match(body.name, "^Held(%d)$"))
			if index == nil or index <= held then
				AntiEsp.isHidden(viewers[body.by], slots[body.name])
			end
		end
	end

	-- Each held sleeper seen in its own slice, then all three retested walled and held on timers 2 s after
	for index: number, now: number in SEEN do
		ask(index)
		harness:slice(now)
	end

	for _, body in BODIES do
		if body.walled == "retest" then
			walled[body.name] = true
			AntiEsp.moved(slots[body.name])
		end
	end

	ask(#SEEN)
	harness:slice(RETESTED)

	-- The walkers walk past their sleepers' groups, one player is made due, and the relay asks once more
	for index: number = 1, 3 do
		viewers[`Walker{index}`].position = PAST
	end

	AntiEsp.moved(slots.Moved)
	ask(#SEEN)

	return { harness = harness, clock = clock, AntiEsp = AntiEsp, slots = slots }
end

-- The bodies a slice cast at, by name, each checked against its ray count
local function cast(world: World): ({ [string]: boolean }, string?)
	local found: { [string]: boolean } = {}

	for _, body in BODIES do
		local count: number = 0
		for _, ray: any in world.harness.rays do
			local offset: vector = ray.to - body.at
			if math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				count += 1
			end
		end

		if count > 0 then
			if count ~= RAYS[body.name] then
				return found, `{count} rays at {body.name}, not its test's {RAYS[body.name]}`
			end

			found[body.name] = true
		end
	end

	return found, nil
end

-- Whether a slice cast at exactly the bodies named
local function exactly(found: { [string]: boolean }, names: { string }): boolean
	local count: number = 0
	for _ in found do
		count += 1
	end

	for _, name: string in names do
		if not found[name] then
			return false
		end
	end

	return count == #names
end

-- 1) A clock that lets each slice take one item before its deadline: each step's cut moves the next slice on a step
local function steps(): (boolean, string?)
	local world: World = build()

	-- Timers then cut, walks then cut, drains then cut, then tests cut before their first, so they begin the next
	for index: number = 1, 4 do
		world.harness:sliceOn(world.clock, CUT_AT, 3)
		if #world.harness.rays ~= 0 then
			return false, `Cut slice {index} cast {#world.harness.rays} rays`
		end
	end

	-- Begun at the tests: what the three cuts let wait, a held sleeper, a walker's sleeper and the moved player
	world.harness:sliceOn(world.clock, CUT_AT)
	local found: { [string]: boolean }, why: string? = cast(world)
	if why then
		return false, `The slice after the cuts cast {why}`
	elseif not exactly(found, { "Held1", "Lying1", "Moved" }) then
		return false, "The slice after the cuts didn't begin at its tests with what each step's cut had let wait"
	end

	-- Begun at the first step again, after the tests ran on: the rest, which that slice's other steps let wait
	world.harness:sliceOn(world.clock, CUT_AT)
	found, why = cast(world)
	if why then
		return false, `The slice after that cast {why}`
	elseif not exactly(found, { "Held2", "Held3", "Lying2", "Lying3", "Near", "Seen", "Far" }) then
		return false, "The slice after that didn't test what the steps after the tests had let wait"
	end

	if world.AntiEsp.cuts() ~= 4 then
		return false, `Four cut slices counted {world.AntiEsp.cuts()} cuts`
	end

	return true, nil
end

-- 2) A clock that cuts every slice after two items, every earlier step holding more than that: tests by the fourth
local function overload(): (boolean, string?)
	local world: World = build()

	for index: number = 1, 4 do
		world.harness:sliceOn(world.clock, CUT_AT, 4)

		local rays: number = #world.harness.rays
		if index < 4 and rays ~= 0 then
			return false, `Overloaded slice {index} cast {rays} rays before the tests' turn`
		elseif index == 4 and rays ~= RAYS.Lying1 then
			return false, `The fourth overloaded slice cast {rays} rays, not its first test's {RAYS.Lying1}`
		end
	end

	return true, nil
end

return function (): (boolean, string | nil)
	for _, part: () -> (boolean, string?) in { steps, overload } do
		local passed: boolean, why: string? = part()
		if not passed then
			return false, why
		end
	end

	return true, nil
end
