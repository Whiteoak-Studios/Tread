--[[
    A hidden pair whose fail-open comes due inside a run that leaves its
    viewer out: a twin asked that run fails it open at once and counts it,
    while the left one, kept by AntiEsp.passed, stays hidden; starved until
    its next ask, the left one fails open there, a run late, and once both
    are tested they cast the same rays, and a slice that tests the left one
    before its next ask spares it the fail-open
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
	{ name = "Failing", kind = "Player", at = vector.create(0, 0, -30), sees = false, walled = true },
	{ name = "Later", kind = "Player", at = vector.create(0, 0, -60), sees = false, walled = true }, -- First asked later
	{ name = "Seen", kind = "Player", at = vector.create(20, 0, 0), sees = false, walled = false },
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

-- The bodies a slice's rays end at, in the order its tests cast them
local function order(side: Twin): { string }
	local named: { string } = {}

	for _, ray: any in side.harness.rays do
		for _, body in BODIES do
			local offset: vector = ray.to - body.at
			if math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH and named[#named] ~= body.name then
				table.insert(named, body.name)
			end
		end
	end

	return named
end

local function same(names: { string }, others: { string }): boolean
	return table.concat(names, " ") == table.concat(others, " ")
end

local function failOpens(side: Twin): number
	local _, _, count: number = side.AntiEsp.counts()

	return count
end

-- One run: the other viewer's ask, then the left viewer's asks, or passed in their place, and the answers
local function run(side: Twin, names: { string }, left: boolean): { boolean }
	local AntiEsp: any = side.AntiEsp
	local answers: { boolean } = {}
	AntiEsp.isHidden(side.viewers.Other, side.slots.Seen)

	if left then
		local slots: { number } = {}
		for _, name: string in names do
			table.insert(slots, side.slots[name])
		end

		AntiEsp.passed(side.viewers.Left, slots, #slots)
	else
		for _, name: string in names do
			table.insert(answers, AntiEsp.isHidden(side.viewers.Left, side.slots[name]))
		end
	end

	return answers
end

-- Two twins through the runs before the left one: the walled pair tested at 0 s, then starved past 0.15 s, the other
-- walled pair first asked at 0.1 s, and the asked twin's ask of the run at 0.2 s failing the first open
local function upToTheLeftRun(): (Twin, Twin, string?)
	local asked: Twin = twin()
	local passed: Twin = twin()

	for _, side: Twin in { asked, passed } do
		run(side, { "Failing" }, false)
		side.harness:slice(0)
		run(side, { "Failing" }, false)
		side.harness:sliceOn(side.clock, 0.1, STARVED)
		run(side, { "Failing", "Later" }, false)
		side.harness:sliceOn(side.clock, 0.2, STARVED)
	end

	local answers: { boolean } = run(asked, { "Failing", "Later" }, false)
	run(passed, { "Failing", "Later" }, true)

	if answers[1] or asked.AntiEsp.reason(asked.viewers.Left.key, asked.slots.Failing) ~= "FailOpen" then
		return asked, passed, "The asked twin's ask past the fail-open didn't fail the pair open"
	elseif failOpens(asked) ~= 1 then
		return asked, passed, `The asked twin counted {failOpens(asked)} fail-opens at the left run, not 1`
	elseif passed.AntiEsp.reason(passed.viewers.Left.key, passed.slots.Failing) ~= "Hidden" then
		return asked, passed, "The left twin's pair didn't stay hidden through the left run"
	elseif failOpens(passed) ~= 0 then
		return asked, passed, `The left twin counted {failOpens(passed)} fail-opens in the run it was left out of`
	end

	return asked, passed, nil
end

return function (): (boolean, string | nil)
	-- 1) Starved until the next ask: the left twin fails the pair open there, a run after the asked one
	local asked: Twin, passed: Twin, why: string? = upToTheLeftRun()
	if why then
		return false, why
	end

	for _, side: Twin in { asked, passed } do
		side.harness:sliceOn(side.clock, 0.25, STARVED)
		if #side.harness.rays ~= 0 then
			return false, "A starved slice cast rays"
		end
	end

	local askedAnswers: { boolean } = run(asked, { "Failing", "Later" }, false)
	local passedAnswers: { boolean } = run(passed, { "Failing", "Later" }, false)

	if askedAnswers[1] or passedAnswers[1] or not askedAnswers[2] or not passedAnswers[2] then
		return false, "The next ask didn't find both twins' failing pair sent and the later pair hidden"
	elseif passed.AntiEsp.reason(passed.viewers.Left.key, passed.slots.Failing) ~= "FailOpen" then
		return false, "The left twin's pair didn't fail open at its next ask"
	elseif failOpens(asked) ~= 1 or failOpens(passed) ~= 1 then
		return false, `The twins counted {failOpens(asked)} and {failOpens(passed)} fail-opens after the next ask`
	end

	-- Both then tested at the next slice from the same queues, with the same rays, and hidden again
	for _, side: Twin in { asked, passed } do
		side.harness:sliceOn(side.clock, 0.3)
	end

	if not same(order(asked), { "Later", "Failing" }) or not same(order(passed), order(asked)) then
		return false, `After the fail-opens the twins tested {table.concat(order(passed), ", ")} with the viewer left`
	end

	askedAnswers = run(asked, { "Failing", "Later" }, false)
	passedAnswers = run(passed, { "Failing", "Later" }, false)
	if not (askedAnswers[1] and passedAnswers[1] and askedAnswers[2] and passedAnswers[2]) then
		return false, "The twins' walled pairs weren't hidden again once tested"
	end

	-- 2) A slice that tests between the left run and its next ask: the asked twin retests its failed-open pair after
	-- the hidden one, from the visible heap, and the left twin its still hidden pair nearest first, so it never fails
	-- open
	asked, passed, why = upToTheLeftRun()
	if why then
		return false, why
	end

	for _, side: Twin in { asked, passed } do
		side.harness:sliceOn(side.clock, 0.25)
	end

	if not same(order(asked), { "Later", "Failing" }) then
		return false, `The asked twin retested {table.concat(order(asked), ", ")}, not the hidden pair first`
	elseif not same(order(passed), { "Failing", "Later" }) then
		return false, `The left twin retested {table.concat(order(passed), ", ")}, not its hidden pairs nearest first`
	end

	passedAnswers = run(passed, { "Failing", "Later" }, false)
	if not (passedAnswers[1] and passedAnswers[2]) or failOpens(passed) ~= 0 then
		return false, `The left twin, tested before its next ask, counted {failOpens(passed)} fail-opens there`
	end

	return true, nil
end
