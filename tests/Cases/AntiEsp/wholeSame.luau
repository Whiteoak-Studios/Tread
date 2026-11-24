--[[
    A slice running whole whose deadline is never reached is the slice not
    running whole: through steps of walks, moves, holds and timers, two
    twins cast every ray the same in the same order and keep every verdict
    and count the same, with no cut
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local STEPS: number = 80
local INTERVAL: number = 0.05 -- Seconds from one slice to the next, a relay tick at 20 Hz
local PATTERN: number = 3 -- One ray end in this many is open, by where it ends and the step
local WALK: vector = vector.create(5, 0, 0) -- Past the example's 4-stud retest, so a walk triggers sleeper groups
local STRAY: vector = vector.create(0, 0, 3) -- A target's move

-- How often each change comes, and the step it first comes at. Both walkers walk on one step, so their sleepers'
-- groups trigger in one slice, and two players are made due beside the queues' rechecks, so pairs from more than
-- one queue or walk wait in one heap under one key, where the order they came due in is the order they are tested
local WALKS: number = 7
local WALK_AT: number = 3
local MOVES: number = 11
local MOVE_AT: number = 5
local TARGET_MOVES: number = 6
local TARGET_MOVE_AT: number = 2
local STRAYS: number = 9
local STRAY_AT: number = 4
local MOVED: { string } = { "Side", "Back" } -- The players made due

-- Each body's name, kind and place, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "First", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Second", kind = "Player", at = vector.create(40, 0, 0), sees = true },
	{ name = "Near", kind = "Player", at = vector.create(0, 0, -30), sees = false },
	{ name = "Side", kind = "Player", at = vector.create(30, 0, -10), sees = false },
	{ name = "Far", kind = "Player", at = vector.create(0, 0, 320), sees = false },
	{ name = "Back", kind = "Player", at = vector.create(-20, 0, 20), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-30, 0, -30), sees = false },
	{ name = "Body", kind = "Body", at = vector.create(30, 0, 30), sees = false },
}

-- The bot viewer's own asks, beside every viewer asking about every body but itself
local EYE_ASKS: { string } = { "Near", "Sleeper", "Body" }

-- A second bot viewer, asked before every other so it is first in anti-ESP's walk, standing apart from the first
-- with the same lying asks: as the wall reads only where a ray ends, its lying pairs keep the first one's verdicts
-- and group times, so the two walk past their groups under one key
local MIRROR_ASKS: { string } = { "Sleeper", "Body" }
local MIRROR_AT: vector = vector.create(0, 0, 12)

-- One harness and its bodies and viewers, built the same on both twins
type Twin = {
	harness: any,
	AntiEsp: any,
	slots: { [string]: number },
	viewers: { [string]: any },
	eye: any,
	mirror: any,
}

local function twin(whole: boolean, step: () -> number): Twin
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	Harness.AntiEsp.useWhole(whole)

	-- A ray ends open in one place of PATTERN, by where it ends and the step
	harness.wall = function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		return (math.floor(finish.x) + math.floor(finish.y * 4) + math.floor(finish.z) + step()) % PATTERN ~= 0
	end

	local built: Twin =
		{ harness = harness, AntiEsp = Harness.AntiEsp, slots = {}, viewers = {}, eye = nil, mirror = nil }
	for _, body in BODIES do
		local slot: number = harness:body(body.kind, body.at)
		built.slots[body.name] = slot

		if body.sees then
			built.viewers[body.name] = harness:viewer(body.name, slot)
		end
	end

	built.eye = harness:viewer("Eye", nil)
	built.mirror = harness:viewer("Mirror", nil)
	built.mirror.position = MIRROR_AT

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
	local step: number = 0
	local function current(): number
		return step
	end

	local plain: Twin = twin(false, current)
	local whole: Twin = twin(true, current)
	local twins: { Twin } = { plain, whole }

	-- Each twin's asks, in one order, giving every answer in it
	local function ask(side: Twin): { boolean }
		local answers: { boolean } = {}

		for _, name: string in MIRROR_ASKS do
			table.insert(answers, side.AntiEsp.isHidden(side.mirror, side.slots[name]))
		end

		for _, body in BODIES do
			local viewer: any = side.viewers[body.name]
			if viewer == nil then
				continue
			end

			for _, other in BODIES do
				if other.name ~= body.name then
					table.insert(answers, side.AntiEsp.isHidden(viewer, side.slots[other.name]))
				end
			end
		end

		for _, name: string in EYE_ASKS do
			table.insert(answers, side.AntiEsp.isHidden(side.eye, side.slots[name]))
		end

		return answers
	end

	for at: number = 0, STEPS - 1 do
		step = at

		for _, side: Twin in twins do
			local harness: any = side.harness
			local first: any = side.viewers.First

			if at % WALKS == WALK_AT then
				local direction: number = (at // WALKS) % 2 == 0 and 1 or -1
				harness:move(side.slots.First, first.position + WALK * direction, first)
				side.eye.position += WALK
				side.mirror.position += WALK
			end

			if at % MOVES == MOVE_AT then
				side.AntiEsp.moved(side.slots.Sleeper)
			end

			if at % TARGET_MOVES == TARGET_MOVE_AT then
				for _, name: string in MOVED do
					side.AntiEsp.moved(side.slots[name])
				end
			end

			if at % STRAYS == STRAY_AT then
				harness:move(side.slots.Near, harness.states[side.slots.Near].position + STRAY)
			end
		end

		local plainAnswers: { boolean } = ask(plain)
		local wholeAnswers: { boolean } = ask(whole)

		for index: number, answer: boolean in plainAnswers do
			if wholeAnswers[index] ~= answer then
				return false, `At step {at} ask {index} answered {wholeAnswers[index]} running whole, {answer} not`
			end
		end

		local now: number = at * INTERVAL
		plain.harness:slice(now)
		whole.harness:slice(now)

		if not sameRays(plain.harness.rays, whole.harness.rays) then
			return false,
				`At step {at} the twins cast {#plain.harness.rays} and {#whole.harness.rays} rays, not the same`
		end

		-- Tests, hidden results, fail-opens, sleepers' tests, sleepers waiting and rays
		local counts: { { number } } = {}
		for index: number, side: Twin in twins do
			local tests: number, hiddenResults: number, failOpens: number = side.AntiEsp.counts()
			local lyingTests: number, lyingWaiting: number = side.AntiEsp.lying()
			counts[index] = { tests, hiddenResults, failOpens, lyingTests, lyingWaiting, side.AntiEsp.rays() }
		end

		for index: number, count: number in counts[1] do
			if counts[2][index] ~= count then
				return false, `At step {at} count {index} read {counts[2][index]} running whole, {count} not`
			end
		end

		for _, body in BODIES do
			for viewer: string, plainViewer: any in plain.viewers do
				local plainReason: string = plain.AntiEsp.reason(plainViewer.key, plain.slots[body.name])
				local wholeReason: string = whole.AntiEsp.reason(whole.viewers[viewer].key, whole.slots[body.name])
				if plainReason ~= wholeReason then
					return false, `At step {at} {viewer}'s pair with {body.name} gave {wholeReason} running whole`
				end
			end
		end

		if plain.AntiEsp.cuts() ~= 0 or whole.AntiEsp.cuts() ~= 0 then
			return false, `At step {at} a slice that never reached its deadline counted a cut`
		end
	end

	return true, nil
end
