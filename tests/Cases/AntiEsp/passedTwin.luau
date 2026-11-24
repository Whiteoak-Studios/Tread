--[[
    Running whole through starved slices, a viewer left out of three runs
    and handed to AntiEsp.passed keeps its pairs as a twin asked every run
    does: the same rays at every slice, both twins failing the same hidden
    pairs open at the same ask once they go untested past the fail-open
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local STARVED: number = 2 -- A slice's late read: the deadline, then its first item's, found passed, so it takes none

-- Each body's name, kind and place, whether it is a viewer, and whether rays to it are walled
local BODIES: { { name: string, kind: string, at: vector, sees: boolean, walled: boolean } } = {
	{ name = "Left", kind = "Player", at = vector.create(0, 0, 0), sees = true, walled = false },
	{ name = "Other", kind = "Player", at = vector.create(0, 0, 50), sees = true, walled = false },
	{ name = "Near", kind = "Player", at = vector.create(0, 0, -30), sees = false, walled = true },
	{ name = "Far", kind = "Player", at = vector.create(0, 0, -300), sees = false, walled = true },
	{ name = "Seen", kind = "Player", at = vector.create(20, 0, 0), sees = false, walled = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-30, 0, 0), sees = false, walled = false },
}

local ASKS: { string } = { "Near", "Far", "Seen", "Sleeper" } -- The left viewer's, each run

-- Each run: whether the left viewer is left out of it, and its slice's time and late read. Every ask in a run that
-- leaves it out finds its hidden pairs inside the 0.15 s fail-open, and the asked run after the starved slices finds
-- them past it
local RUNS: { { left: boolean, at: number, late: number } } = {
	{ left = false, at = 0, late = math.huge },
	{ left = true, at = 0.05, late = STARVED },
	{ left = true, at = 0.1, late = STARVED },
	{ left = true, at = 0.16, late = STARVED },
	{ left = false, at = 0.2, late = math.huge },
	{ left = true, at = 0.25, late = math.huge },
	{ left = false, at = 0.3, late = math.huge },
}

type Twin = {
	harness: any,
	clock: any,
	AntiEsp: any,
	slots: { [string]: number },
	viewers: { [string]: any },
}

local function twin(): Twin
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	Harness.AntiEsp.useWhole(true)

	local built: Twin = { harness = harness, clock = clock, AntiEsp = Harness.AntiEsp, slots = {}, viewers = {} }
	for _, body in BODIES do
		built.slots[body.name] = harness:body(body.kind, body.at)
		if body.sees then
			built.viewers[body.name] = harness:viewer(body.name, built.slots[body.name])
		end
	end

	-- A ray is blocked when it ends at a walled body
	harness.wall = function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		for _, body in BODIES do
			local offset: vector = finish - body.at
			if body.walled and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				return true
			end
		end

		return false
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

	for index: number, run in RUNS do
		local answers: { { boolean } } = {}

		for which: number, side: Twin in { asked, passed } do
			local AntiEsp: any = side.AntiEsp
			local left: any = side.viewers.Left
			local slots: { number } = {}
			answers[which] = {}

			AntiEsp.isHidden(side.viewers.Other, side.slots.Seen)

			for _, name: string in ASKS do
				table.insert(slots, side.slots[name])
			end

			if side == passed and run.left then
				AntiEsp.passed(left, slots, #slots)
			else
				for _, slot: number in slots do
					table.insert(answers[which], AntiEsp.isHidden(left, slot))
				end
			end

			side.harness:sliceOn(side.clock, run.at, run.late)
		end

		if not run.left then
			for place: number, answer: boolean in answers[1] do
				if answers[2][place] ~= answer then
					return false, `Run {index}'s ask of {ASKS[place]} answered {answers[2][place]} after left runs`
				end
			end
		end

		if not sameRays(asked.harness.rays, passed.harness.rays) then
			local rays: number = #passed.harness.rays
			return false,
				`Run {index}'s slice cast {rays} rays with the viewer left, not the same {#asked.harness.rays}`
		end
	end

	-- Both hidden pairs failed open at the asked run past the starved slices, and were tested hidden again after
	for _, side: Twin in { asked, passed } do
		local _, _, failOpens: number = side.AntiEsp.counts()
		if failOpens ~= 2 then
			return false, `A twin counted {failOpens} fail-opens, not its two hidden pairs'`
		end

		for _, name: string in ASKS do
			local reason: string = side.AntiEsp.reason(side.viewers.Left.key, side.slots[name])
			local other: string = asked.AntiEsp.reason(asked.viewers.Left.key, asked.slots[name])
			if reason ~= other then
				return false, `The left viewer's pair with {name} read {reason} with it left, {other} with it asked`
			end
		end
	end

	return true, nil
end
