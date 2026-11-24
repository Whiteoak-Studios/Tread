--[[
    A viewer the relay leaves out of three runs in a row, its pairs handed
    to AntiEsp.passed each time, keeps them as a twin asked every run does:
    the same rays at the same slices, its visible pair still visible and
    its hidden one still hidden, tested, in the answers and at its next ask
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row

-- Each body's name, kind and place, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "Left", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Other", kind = "Player", at = vector.create(0, 0, 50), sees = true },
	{ name = "Seen", kind = "Player", at = vector.create(20, 0, 0), sees = false },
	{ name = "Walled", kind = "Player", at = vector.create(0, 0, -30), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-30, 0, 0), sees = false },
}

local ASKS: { string } = { "Seen", "Walled", "Sleeper" } -- The left viewer's, each run
local LEFT_RUNS: { [number]: boolean } = { [2] = true, [3] = true, [4] = true } -- The runs that leave it out

-- Each run's slice, after its asks: the walled player's 30 Hz near rechecks fall in the first three, and the 2 Hz
-- rechecks of the seen player and the other viewer's at the last
local TIMES: { number } = { 0, 0.04, 0.08, 0.5, 0.55 }

type Twin = {
	harness: any,
	AntiEsp: any,
	slots: { [string]: number },
	viewers: { [string]: any },
}

local function twin(): Twin
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local built: Twin = { harness = harness, AntiEsp = Harness.AntiEsp, slots = {}, viewers = {} }

	for _, body in BODIES do
		local slot: number = harness:body(body.kind, body.at)
		built.slots[body.name] = slot

		if body.sees then
			built.viewers[body.name] = harness:viewer(body.name, slot)
		end
	end

	-- A ray is blocked when it ends at the walled player
	local walled: vector = harness.states[built.slots.Walled].position
	harness.wall = function (origin: vector, direction: vector): boolean
		local offset: vector = origin + direction - walled

		return math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH
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

-- Whether a slot's bit is set in the first viewer's row of an answers buffer
local function bit(row: buffer, slot: number): boolean
	return bit32.btest(buffer.readu8(row, slot // BITS), bit32.lshift(1, slot % BITS))
end

return function (): (boolean, string | nil)
	local asked: Twin = twin()
	local passed: Twin = twin()
	local twins: { Twin } = { asked, passed }

	for run: number, now: number in TIMES do
		for _, side: Twin in twins do
			local AntiEsp: any = side.AntiEsp
			local left: any = side.viewers.Left

			-- The answers a relay worker would take for the left viewer before this run
			if side == passed and run == 3 then
				local answers: any = AntiEsp.answers({ left })
				for _, name: string in ASKS do
					local slot: number = side.slots[name]
					local visible: boolean = bit(answers.visible, slot)

					if not bit(answers.quiet, slot) then
						return false, `The answers read {name}'s kept pair as one an ask would change`
					elseif visible ~= (name ~= "Walled") then
						return false, `The answers read {name}'s kept pair as visible {visible}`
					end
				end
			end

			AntiEsp.isHidden(side.viewers.Other, side.slots.Seen)

			local slots: { number } = {}
			for _, name: string in ASKS do
				table.insert(slots, side.slots[name])
			end

			if side == passed and LEFT_RUNS[run] then
				AntiEsp.passed(left, slots, #slots)
			else
				for _, slot: number in slots do
					AntiEsp.isHidden(left, slot)
				end
			end

			side.harness:slice(now)
		end

		if not sameRays(asked.harness.rays, passed.harness.rays) then
			local rays: number = #passed.harness.rays
			return false,
				`The slice at {now} s cast {rays} rays with the viewer left, not {#asked.harness.rays} the same`
		end
	end

	-- The viewer is asked again: the seen player visible, the walled one hidden, each tested and never restarted
	local AntiEsp: any = passed.AntiEsp
	local left: any = passed.viewers.Left

	if AntiEsp.isHidden(left, passed.slots.Seen) then
		return false, "The left viewer's visible pair restarted hidden"
	elseif not AntiEsp.isHidden(left, passed.slots.Walled) then
		return false, "The left viewer's hidden pair was sent"
	elseif AntiEsp.reason(left.key, passed.slots.Walled) ~= "Hidden" then
		return false, `The left viewer's hidden pair read {AntiEsp.reason(left.key, passed.slots.Walled)}, not Hidden`
	elseif AntiEsp.reason(left.key, passed.slots.Sleeper) ~= "Clear" then
		return false, `The left viewer's sleeper pair read {AntiEsp.reason(left.key, passed.slots.Sleeper)}, not Clear`
	end

	local askedCounts: { number } = {}
	local passedCounts: { number } = {}
	askedCounts[1], askedCounts[2], askedCounts[3] = asked.AntiEsp.counts()
	passedCounts[1], passedCounts[2], passedCounts[3] = AntiEsp.counts()

	for index: number, count: number in askedCounts do
		if passedCounts[index] ~= count then
			return false, `Count {index} read {passedCounts[index]} with the viewer left, {count} with it asked`
		end
	end

	return true, nil
end
