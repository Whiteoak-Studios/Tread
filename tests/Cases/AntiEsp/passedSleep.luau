--[[
    A target that falls asleep or wakes while its viewer is left out of a
    run is moved to its new schedule by AntiEsp.passed as an ask moves it:
    retested at once with its new kind's rays, the same rays and verdicts
    as a twin asked that run, so no sleeper keeps a verdict from standing
    rays and no woken player one from lying rays
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LOW: number = 2 -- Studs above the ground below which a wall blocks every ray
local SWITCHED_AT: number = 0.1 -- Well before either pair's own next test, the standing one's 2 Hz recheck
local THEN: number = 0.15

-- Each body's name, kind and place, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "Left", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Other", kind = "Player", at = vector.create(0, 0, 50), sees = true },
	{ name = "Sleeping", kind = "Player", at = vector.create(20, 0, 0), sees = false }, -- Falls asleep
	{ name = "Waking", kind = "Sleeper", at = vector.create(-30, 0, 0), sees = false }, -- Wakes
}

local ASKS: { string } = { "Sleeping", "Waking" }
local SWITCH: { [string]: string } = { Sleeping = "Sleeper", Waking = "Player" }

type Twin = {
	harness: any,
	AntiEsp: any,
	Slots: any,
	slots: { [string]: number },
	viewers: { [string]: any },
}

local function twin(): Twin
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Harness.clock().read)
	Harness.AntiEsp.useWhole(true)

	-- A low wall everywhere: a lying body's rays are blocked, a standing one's head ray is open
	harness.wall = function (origin: vector, direction: vector): boolean
		return (origin + direction).y < LOW
	end

	local built: Twin =
		{ harness = harness, AntiEsp = Harness.AntiEsp, Slots = Harness.Slots, slots = {}, viewers = {} }
	for _, body in BODIES do
		built.slots[body.name] = harness:body(body.kind, body.at)
		if body.sees then
			built.viewers[body.name] = harness:viewer(body.name, built.slots[body.name])
		end
	end

	return built
end

-- Every ray's origin and end the same and in the same order
local function sameRays(rays: { any }, others: { any }): boolean
	if #rays ~= #others then
		return false
	end

	for index: number, ray: any in rays do
		local other: any = others[index]
		if ray.origin ~= other.origin or ray.to ~= other.to then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local asked: Twin = twin()
	local passed: Twin = twin()
	local twins: { Twin } = { asked, passed }

	-- Both pairs tested at 0 s: the standing one seen over the wall, the lying one blocked
	for _, side: Twin in twins do
		for _, name: string in ASKS do
			side.AntiEsp.isHidden(side.viewers.Left, side.slots[name])
		end

		side.AntiEsp.isHidden(side.viewers.Other, side.slots.Sleeping)
		side.harness:slice(0)
	end

	-- One falls asleep and the other wakes, then a run asks the twin's viewer and leaves the other's out
	for _, side: Twin in twins do
		for _, name: string in ASKS do
			side.Slots.setEntry(side.slots[name], { kind = SWITCH[name], rig = "A" })
		end

		side.AntiEsp.isHidden(side.viewers.Other, side.slots.Sleeping)

		local slots: { number } = {}
		for _, name: string in ASKS do
			table.insert(slots, side.slots[name])
		end

		if side == passed then
			side.AntiEsp.passed(side.viewers.Left, slots, #slots)
		else
			for _, slot: number in slots do
				side.AntiEsp.isHidden(side.viewers.Left, slot)
			end
		end
	end

	-- Each slice after: both pairs retested at once on their new schedules, the same in both twins
	for _, now: number in { SWITCHED_AT, THEN } do
		for _, side: Twin in twins do
			side.harness:slice(now)
		end

		if #passed.harness.rays == 0 and now == SWITCHED_AT then
			return false, "The left viewer's pairs weren't retested at once once their targets slept and woke"
		elseif not sameRays(asked.harness.rays, passed.harness.rays) then
			local rays: number = #passed.harness.rays
			return false,
				`The slice at {now} s cast {rays} rays with the viewer left, not the same {#asked.harness.rays}`
		end

		for _, side: Twin in twins do
			for _, name: string in ASKS do
				side.AntiEsp.isHidden(side.viewers.Left, side.slots[name])
			end

			side.AntiEsp.isHidden(side.viewers.Other, side.slots.Sleeping)
		end
	end

	for _, name: string in ASKS do
		local reason: string = passed.AntiEsp.reason(passed.viewers.Left.key, passed.slots[name])
		local other: string = asked.AntiEsp.reason(asked.viewers.Left.key, asked.slots[name])
		if reason ~= other then
			return false, `The left viewer's pair with {name} read {reason} with it left, {other} with it asked`
		end
	end

	return true, nil
end
