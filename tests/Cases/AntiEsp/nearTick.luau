--[[
    A near hidden pair is retested once a server tick, at the first slice
    that finds its tick, far and visible pairs keep their rates, and a move,
    a fail-open, a new life or a wake tests it at the next slice
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local NEAR: number = 200 -- Studs from the viewer, inside the example's 250-stud near radius
local FAR: number = 300
local TICKS: number = 12 -- Ticks a pair's run on the derived ticks spans
local SLICES: number = 3 -- Slices a tick, at 60 Heartbeats a second and the example's 20 Hz
local LATE: number = 2 -- A cut slice's first stand-in clock read past its deadline, the one before its first test
local BUDGET: number = 1 -- Seconds a slice run by hand may take on the stand-in clock, which never reaches it

local Example: any = Environment.load(EXAMPLE)
local RATE: number = Example.shared().rates.simulation -- The example's server ticks a second
local STEP: number = 1 / (RATE * SLICES) -- Seconds between slices

-- One pair's scene: a harness on a stand-in clock, its viewer at the origin and its target asked about once
type Scene = { harness: any, clock: any, viewer: any, target: number, Harness: any }

-- A scene whose target stands a distance ahead of the viewer, every ray to it blocked or none
local function scene(distance: number, blocked: boolean): Scene
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	if blocked then
		harness.wall = Harness.solid
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -distance))
	harness.AntiEsp.isHidden(viewer, target)

	return { harness = harness, clock = clock, viewer = viewer, target = target, Harness = Harness }
end

-- Slice number at, on the tick its time falls in unless one is given, cut when late is, then the relay's ask; whether
-- it tested the pair
local function at(this: Scene, slice: number, tick: number?, late: number?): boolean
	this.harness:sliceOn(this.clock, slice * STEP, late, tick)
	local tested: boolean = #this.harness.rays > 0
	this.harness.AntiEsp.isHidden(this.viewer, this.target)

	return tested
end

-- The slices of a list that tested, as "0,3,6"
local function listed(tested: { boolean }, from: number): string
	local found: { string } = {}
	for index: number, test: boolean in tested do
		if test then
			table.insert(found, tostring(from + index - 1))
		end
	end

	return table.concat(found, ",")
end

-- The slices from 0 a pair on a timed schedule tests in, as the module keeps it: each test due an interval after its
-- slice's time, at the first slice whose time reaches that
local function timed(interval: number, count: number): string
	local tested: { boolean } = table.create(count, false)
	local due: number = 0
	for slice: number = 0, count - 1 do
		local now: number = slice * STEP
		if now >= due then
			tested[slice + 1] = true
			due = now + interval
		end
	end

	return listed(tested, 0)
end

-- The first slice of each tick from 0 for count slices
local function firsts(count: number): string
	local tested: { boolean } = table.create(count, false)
	for slice: number = 0, count - 1 do
		tested[slice + 1] = slice % SLICES == 0
	end

	return listed(tested, 0)
end

-- One pair over count slices from 0 on the ticks their times fall in, the slices that tested it
local function over(this: Scene, count: number): string
	local tested: { boolean } = {}
	for slice: number = 0, count - 1 do
		tested[slice + 1] = at(this, slice)
	end

	return listed(tested, 0)
end

return function (): (boolean, string | nil)
	local server: any = Example.server()
	local count: number = TICKS * SLICES

	-- 1) Over 12 ticks of three slices, a near hidden pair is tested at each tick's first slice alone and stays hidden,
	-- a far hidden one every 0.1 s and a visible one every 0.5 s, both by their timers whatever the tick
	local near: Scene = scene(NEAR, true)
	local found: string = over(near, count)
	if found ~= firsts(count) then
		return false, `A near hidden pair was tested at slices {found}, not each tick's first, {firsts(count)}`
	elseif not near.harness.AntiEsp.isHidden(near.viewer, near.target) then
		return false, "A near hidden pair tested once a tick turned visible"
	end

	local timers: { { distance: number, blocked: boolean, interval: number, kind: string } } = {
		{ distance = FAR, blocked = true, interval = 1 / server.antiEsp.hiddenRate, kind = "far hidden" },
		{ distance = NEAR, blocked = false, interval = 1 / server.antiEsp.visibleRate, kind = "near visible" },
		{ distance = FAR, blocked = false, interval = 1 / server.antiEsp.visibleRate, kind = "far visible" },
	}

	for _, timer in timers do
		local this: Scene = scene(timer.distance, timer.blocked)
		local wanted: string = timed(timer.interval, count)
		found = over(this, count)
		if found ~= wanted then
			return false, `A {timer.kind} pair was tested at slices {found}, not {wanted} by its {timer.interval} s`
		elseif found == firsts(count) then
			return false, `A {timer.kind} pair was tested once a tick`
		end
	end

	-- 2) Two slices handed the same tick test once, and a slice handed a tick two on tests once, not once for each
	local ticks: { { tick: number, tested: boolean } } = {
		{ tick = 0, tested = true },
		{ tick = 1, tested = true },
		{ tick = 1, tested = false },
		{ tick = 3, tested = true },
		{ tick = 3, tested = false },
		{ tick = 4, tested = true },
	}

	local handed: Scene = scene(NEAR, true)
	for slice: number, row in ticks do
		local tested: boolean = at(handed, slice - 1, row.tick)
		if tested ~= row.tested then
			return false, `A near hidden pair's slice {slice - 1} handed tick {row.tick} tested {tested}`
		end
	end

	-- 3) Left out, the tick is the world's clock, which the times here would put a tick behind
	local world: Scene = scene(NEAR, true)
	local clocks: { { clock: number, tested: boolean } } = {
		{ clock = 7, tested = true },
		{ clock = 7, tested = false },
		{ clock = 8, tested = true },
		{ clock = 8, tested = false },
	}

	for slice: number, row in clocks do
		world.harness.world.clock = row.clock
		world.clock.reads = 0
		world.clock.late = math.huge
		table.clear(world.harness.rays)
		world.harness.AntiEsp.run(BUDGET, (slice - 1) * STEP)

		if (#world.harness.rays > 0) ~= row.tested then
			return false, `A slice with no tick at the world's clock {row.clock} cast {#world.harness.rays} rays`
		end
	end

	-- 4) A move inside a tick tests the pair again that tick, and the next tick tests it as before
	local moved: Scene = scene(NEAR, true)
	local before: { boolean } = { at(moved, 0), at(moved, 1), at(moved, 2), at(moved, 3) }
	moved.harness.AntiEsp.moved(moved.target)
	local after: { boolean } = { at(moved, 4), at(moved, 5), at(moved, 6) }

	if listed(before, 0) ~= "0,3" or listed(after, 4) ~= "4,6" then
		return false, `Around a move inside tick 1 the pair was tested at {listed(before, 0)} and {listed(after, 4)}`
	end

	-- 5) Starved from slice 1, the pair fails open at the first ask past failOpen, is tested at the next slice, and
	-- from there at each tick's first
	local starved: Scene = scene(NEAR, true)
	at(starved, 0)
	local failed: number? = nil
	for slice: number = 1, count do
		if at(starved, slice, nil, LATE) then
			return false, `A starved slice {slice} tested the pair`
		end

		local reason: string = starved.harness.AntiEsp.reason(starved.viewer.key, starved.target)
		if reason == "FailOpen" then
			failed = slice
			break
		elseif reason ~= "Hidden" then
			return false, `The starved pair was {reason} after slice {slice}`
		end
	end

	local due: number = 1
	while due * STEP <= server.antiEsp.failOpen do
		due += 1
	end

	if failed ~= due then
		return false, `The starved pair failed open after slice {failed}, not {due}, the first past failOpen`
	end

	local retest: number = due + 1
	local nextTick: number = (retest // SLICES + 1) * SLICES
	local rest: { boolean } = {}
	for slice: number = retest, nextTick + SLICES do
		rest[slice - retest + 1] = at(starved, slice)
	end

	local wanted: string = `{retest},{nextTick},{nextTick + SLICES}`
	if listed(rest, retest) ~= wanted then
		return false, `After failing open the pair was tested at {listed(rest, retest)}, not {wanted}`
	elseif starved.harness.AntiEsp.reason(starved.viewer.key, starved.target) ~= "Hidden" then
		return false, "The pair failed open was not hidden again once tested"
	end

	-- 6) A new life is tested at the next slice, and a sleep and a wake each at the next slice, then once a tick
	local reborn: Scene = scene(NEAR, true)
	local lives: { boolean } = { at(reborn, 0), at(reborn, 1), at(reborn, 2), at(reborn, 3) }
	reborn.harness:reborn(reborn.target)
	reborn.harness.AntiEsp.isHidden(reborn.viewer, reborn.target)
	for slice: number = 4, 9 do
		lives[slice + 1] = at(reborn, slice)
	end

	if listed(lives, 0) ~= "0,3,4,6,9" then
		return false, `Around a new life after slice 3 the pair was tested at {listed(lives, 0)}, not 0,3,4,6,9`
	end

	local slept: Scene = scene(NEAR, true)
	local Slots: any = slept.Harness.Slots
	local naps: { boolean } = { at(slept, 0), at(slept, 1), at(slept, 2), at(slept, 3) }
	Slots.setEntry(slept.target, { kind = "Sleeper", rig = "A" })
	slept.harness.AntiEsp.isHidden(slept.viewer, slept.target)
	naps[5] = at(slept, 4)

	Slots.setEntry(slept.target, { kind = "Player", rig = "A" })
	slept.harness.AntiEsp.isHidden(slept.viewer, slept.target)
	for slice: number = 5, 9 do
		naps[slice + 1] = at(slept, slice)
	end

	if listed(naps, 0) ~= "0,3,4,5,6,9" then
		return false, `Around a sleep after slice 3 and a wake after 4 the pair was tested at {listed(naps, 0)}`
	end

	return true, nil
end
