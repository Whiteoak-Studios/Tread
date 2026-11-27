--[[
    ParallelStep's probes on clones of the step worker: P9's loads, P2's
    casts, P7's overlaps and P3's battery, each clone's answers compared
    with the main thread's, and the judge giving their lines and problems
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local Builtins = require(ServerScriptService.Server.Parallel.Builtins)
local Pool = require(ServerScriptService.Server.Parallel.Pool)
local Queries = require(ServerScriptService.Server.Parallel.Queries)
local Work = require(ServerScriptService.Server.Parallel.Work)

-- The Actor every step worker is cloned from, which never works itself
local Template = ServerScriptService.Server.Parallel.StepWorker

local WORKERS: number = require(ServerScriptService.Server.Config.Parallel).step.workers
local SLOTS: number = require(ServerScriptService.Server.Config.Parallel).step.slots
local BOXES: number = require(ServerScriptService.Server.Config.Parallel).step.boxes
local SMALL_RADIUS: number = require(ServerScriptService.Server.Config.Parallel).step.smallRadius
local SLOT_SEED: number = require(ServerScriptService.Server.Config.Parallel).step.slotSeed
local PLAN_SEED: number = require(ServerScriptService.Server.Config.Parallel).step.planSeed
local BOX_SEED: number = require(ServerScriptService.Server.Config.Parallel).step.boxSeed
local ANSWER_WAIT: number = require(ServerScriptService.Server.Config.Parallel).step.answerWait
local CONTENT: string = "TestContent" -- The folder under the Workspace whose BaseParts P2 indexes its hits by
local SIDES: number = 2 -- The hull spans the step's radius either side of its center
local PREFIX: string = "ParallelStep" -- What each of the probe's lines begins with
local MILLISECONDS: number = 1000
local TIME: string = "%.3f ms"
local HASH: string = "%08x"
local NONE: string = "none" -- A line's first difference when there is none
local LIST_SEPARATOR: string = ", "
local CLAUSE_SEPARATOR: string = "; "

-- A step worker's loads in the order it runs them, each attribute true or its failure's message
local LOADS: { string } =
	{ Work.CONFIG, Work.ENGINE, Work.WORLD, Work.BUILTINS, Work.QUERIES, Work.CASTS, Work.WORLD_BUILT }

-- P7's two arms in the order they run, the serial one first
local ARMS: { { name: string, topic: string } } = {
	{ name = "serial", topic = Work.OVERLAP },
	{ name = "parallel", topic = Work.OVERLAP_PARALLEL },
}

type Collision = State.Collision
type Tally = Queries.Tally
type OverlapTally = Queries.OverlapTally
type Result = Builtins.Result

-- P9's check as one clone answered it
export type Check = {
	same: boolean, -- Whether its own include list held the main thread's instances in their order
	own: number, -- Entries in its own list
	received: number, -- Entries in the list it was sent
}

-- P9: each clone's load attributes as read, and its answer to the check or the error it gave, by its index
export type Loads = {
	loads: { [number]: { [string]: unknown } },
	checks: { [number]: Check },
	failures: { [number]: string },
}

-- One clone's P2 answer, its results compared with the main thread's
export type Cast = {
	hash: number, -- Its plan's
	seconds: number, -- Its cast's, by its own os.clock()
	tallies: { Tally }, -- The main thread's results against its, a kind each in Queries.KINDS order
}

-- P2: the main thread's plan, cast and results, and each clone's answer or error by its index
export type Casts = {
	slots: number,
	parts: number, -- BaseParts under the test content, which a hit's index counts in
	hash: number, -- The main thread's plan's
	seconds: number, -- Its cast's
	tallies: { Tally }, -- Its results against themselves, so only their hits count
	casts: { [number]: Cast },
	failures: { [number]: string },
}

-- One of P7's arms: each clone's answers against the main thread's, or its error, by its index
export type Arm = {
	name: string,
	tallies: { [number]: OverlapTally },
	failures: { [number]: string },
}

-- P7: the main thread's boxes and those it found overlapping, and each arm in the order they ran
export type Overlaps = {
	boxes: number,
	overlapping: number,
	arms: { Arm },
}

-- P3: the main thread's battery, and each clone's or its error by its index
export type Battery = {
	main: Result,
	results: { [number]: Result },
	failures: { [number]: string },
}

-- Every probe's figures, a probe that never ran left out
export type Figures = {
	workers: number,
	wait: number, -- Seconds each probe's answers had
	loads: Loads?,
	casts: Casts?,
	overlaps: Overlaps?,
	battery: Battery?,
	stopped: string?, -- Why the run stopped short
}

-- A piece of a clone's P2 results and where it goes
type Piece = {
	offset: number,
	piece: buffer,
}

-- A clone's closing P2 fire
type Closing = {
	total: number,
	hash: number,
	seconds: number,
	failure: string?,
}

local Step = {}

local function milliseconds(seconds: number): string
	return string.format(TIME, seconds * MILLISECONDS)
end

--[[
    A problem naming the clones of the probe that gave no answer within the
    wait, and nil when every one did
--]]

local function silence(probe: string, figures: Figures, answered: (worker: number) -> boolean): string?
	local silent: { string } = {}
	for worker: number = 1, figures.workers do
		if not answered(worker) then
			table.insert(silent, `{worker}`)
		end
	end

	if #silent == 0 then
		return nil
	end

	local noun: string = #silent == 1 and "clone" or "clones"

	return `{probe}: no answer from {noun} {table.concat(silent, LIST_SEPARATOR)} within {figures.wait} s`
end

-- P9's lines and problems: each clone's loads, then its answer to the include list check
local function judgeLoads(figures: Figures, loads: Loads, lines: { string }, problems: { string })
	for worker: number = 1, figures.workers do
		local read: { [string]: unknown } = loads.loads[worker] or {}
		local clauses: { string } = {}
		local failed: { string } = {}

		for _, attribute: string in LOADS do
			local value: unknown = read[attribute]
			if value == true then
				table.insert(clauses, `{attribute} ok`)
				continue
			end

			local said: string = type(value) == "string" and `failed: {value}` or "never set"
			table.insert(clauses, `{attribute} {said}`)
			table.insert(failed, `{attribute} {said}`)
		end

		if #failed > 0 then
			table.insert(problems, `P9 clone {worker}: {table.concat(failed, CLAUSE_SEPARATOR)}`)
		end

		local check: Check? = loads.checks[worker]
		local failure: string? = loads.failures[worker]
		local answer: string = `no answer to the check within {figures.wait} s`

		if check then
			local counts: string = `{check.own} in its own list against {check.received} sent`
			answer = `include list the same, {counts}`

			if not check.same then
				answer = `include list differs, {counts}`
				table.insert(problems, `P9 clone {worker}: its include list differs, {counts}`)
			end
		elseif failure then
			answer = `check failed: {failure}`
			table.insert(problems, `P9 clone {worker}: its check failed: {failure}`)
		end

		table.insert(lines, `{PREFIX} P9 clone {worker}: {table.concat(clauses, LIST_SEPARATOR)}; {answer}`)
	end

	local silent: string? = silence("P9", figures, function (worker: number): boolean
		return loads.checks[worker] ~= nil or loads.failures[worker] ~= nil
	end)

	if silent then
		table.insert(problems, silent)
	end
end

-- P2's lines and problems: the main thread's plan and hits, then each clone's results against them
local function judgeCasts(figures: Figures, casts: Casts, lines: { string }, problems: { string })
	local hits: { string } = {}
	for _, tally: Tally in casts.tallies do
		table.insert(hits, `{tally.kind} {tally.hits} of {tally.queries}`)

		if tally.hits == 0 then
			table.insert(problems, `P2 main: {tally.kind} hit nothing in {tally.queries} queries`)
		end
	end

	local planned: string = `{casts.slots} slots of {casts.parts} parts, plan hash {string.format(HASH, casts.hash)}`
	local head: string = `{PREFIX} P2 main: {planned}, cast {milliseconds(casts.seconds)}`
	table.insert(lines, `{head}; hits {table.concat(hits, LIST_SEPARATOR)}`)

	for worker: number = 1, figures.workers do
		local cast: Cast? = casts.casts[worker]
		local failure: string? = casts.failures[worker]

		if not cast then
			local said: string = `no answer within {figures.wait} s`
			if failure then
				said = `failed: {failure}`
				table.insert(problems, `P2 clone {worker}: failed: {failure}`)
			end

			table.insert(lines, `{PREFIX} P2 clone {worker}: {said}`)
			continue
		end

		local hash: string = string.format(HASH, cast.hash)
		if cast.hash ~= casts.hash then
			local against: string = `against the main thread's {string.format(HASH, casts.hash)}`
			table.insert(problems, `P2 clone {worker}: plan hash {hash} {against}`)
		end

		local kinds: { string } = {}
		local first: string = NONE
		for _, tally: Tally in cast.tallies do
			local differed: string = `{tally.differing} differing, {tally.signOnly} sign only`
			local counted: string = `{tally.queries} queries, {differed}, {tally.missing} missing, {tally.hits} hits`
			table.insert(kinds, `{tally.kind} {counted}`)

			local found: string? = tally.first
			if found and first == NONE then
				first = `{tally.kind} {found}`
			end

			if tally.differing > 0 then
				local share: string = `{tally.differing} of {tally.queries} queries differing`
				local split: string = `{tally.signOnly} sign only, {tally.missing} missing`
				table.insert(problems, `P2 clone {worker}: {tally.kind} has {share}, {split}, first {found}`)
			end
		end

		local timed: string =
			`cast {milliseconds(cast.seconds)} against the main thread's {milliseconds(casts.seconds)}`
		local clauses: { string } =
			{ `plan hash {hash}`, table.concat(kinds, CLAUSE_SEPARATOR), `first difference {first}`, timed }
		table.insert(lines, `{PREFIX} P2 clone {worker}: {table.concat(clauses, CLAUSE_SEPARATOR)}`)
	end

	local silent: string? = silence("P2", figures, function (worker: number): boolean
		return casts.casts[worker] ~= nil or casts.failures[worker] ~= nil
	end)

	if silent then
		table.insert(problems, silent)
	end
end

-- P7's lines and problems: the main thread's boxes, then each clone's arms against them
local function judgeOverlaps(figures: Figures, overlaps: Overlaps, lines: { string }, problems: { string })
	table.insert(lines, `{PREFIX} P7 main: {overlaps.boxes} boxes, {overlaps.overlapping} overlapping`)

	if overlaps.overlapping == 0 then
		table.insert(problems, `P7 main: none of its {overlaps.boxes} boxes overlaps`)
	elseif overlaps.overlapping >= overlaps.boxes then
		table.insert(problems, `P7 main: every one of its {overlaps.boxes} boxes overlaps`)
	end

	for worker: number = 1, figures.workers do
		local clauses: { string } = {}

		for _, arm: Arm in overlaps.arms do
			local tally: OverlapTally? = arm.tallies[worker]
			local failure: string? = arm.failures[worker]

			if tally then
				local first: string = tally.first or NONE
				local counts: string = `{tally.boxes} boxes, {tally.differing} differing`
				local rest: string = `{tally.overlapping} overlapping, {tally.missing} missing`
				table.insert(clauses, `{arm.name} {counts}, {rest}, first difference {first}`)

				if tally.differing > 0 then
					local counted: string = `{tally.differing} of {tally.boxes} boxes answered differently`
					local named: string = `P7 clone {worker} {arm.name}`
					table.insert(problems, `{named}: {counted}, {tally.missing} missing, first {first}`)
				end
			elseif failure then
				table.insert(clauses, `{arm.name} failed: {failure}`)
				table.insert(problems, `P7 clone {worker} {arm.name}: failed: {failure}`)
			else
				table.insert(clauses, `{arm.name} no answer within {figures.wait} s`)
			end
		end

		table.insert(lines, `{PREFIX} P7 clone {worker}: {table.concat(clauses, CLAUSE_SEPARATOR)}`)
	end

	for _, arm: Arm in overlaps.arms do
		local silent: string? = silence(`P7 {arm.name}`, figures, function (worker: number): boolean
			return arm.tallies[worker] ~= nil or arm.failures[worker] ~= nil
		end)

		if silent then
			table.insert(problems, silent)
		end
	end
end

-- P3's lines and problems: the main thread's battery, then each clone's section by section against it
local function judgeBattery(figures: Figures, battery: Battery, lines: { string }, problems: { string })
	local main: Result = battery.main
	local ran: string = `{#main.sections} sections, {main.values} values, hash {string.format(HASH, main.hash)}`
	table.insert(lines, `{PREFIX} P3 main: {ran}, timing loop {string.format(TIME, main.loopMs)}`)

	for worker: number = 1, figures.workers do
		local result: Result? = battery.results[worker]
		local failure: string? = battery.failures[worker]

		if not result then
			local said: string = `no answer within {figures.wait} s`
			if failure then
				said = `failed: {failure}`
				table.insert(problems, `P3 clone {worker}: failed: {failure}`)
			end

			table.insert(lines, `{PREFIX} P3 clone {worker}: {said}`)
			continue
		end

		local differences: { string } = Builtins.differences(main, result)
		local matched: string = "every section matches"
		if #differences > 0 then
			matched = `{#differences} differences: {table.concat(differences, CLAUSE_SEPARATOR)}`
			table.insert(problems, `P3 clone {worker}: {table.concat(differences, CLAUSE_SEPARATOR)}`)
		end

		local loop: string = `timing loop {string.format(TIME, result.loopMs)}`
		local timed: string = `{loop} against the main thread's {string.format(TIME, main.loopMs)}`
		table.insert(lines, `{PREFIX} P3 clone {worker}: {#result.sections} sections, {matched}; {timed}`)
	end

	local silent: string? = silence("P3", figures, function (worker: number): boolean
		return battery.results[worker] ~= nil or battery.failures[worker] ~= nil
	end)

	if silent then
		table.insert(problems, silent)
	end
end

--[[
    The probes' figures turned into a line a probe a clone, with the main
    thread's own line first in each, and every problem found, each naming
    its probe, its clone and what differed. Times are printed and never
    judged, and a probe that never ran is a problem of its own
--]]

function Step.judge(figures: Figures): ({ string }, { string })
	local lines: { string } = {}
	local problems: { string } = {}

	local stopped: string? = figures.stopped
	if stopped then
		table.insert(problems, `stopped short: {stopped}`)
	end

	local loads: Loads? = figures.loads
	if loads then
		judgeLoads(figures, loads, lines, problems)
	else
		table.insert(problems, "P9 did not run")
	end

	local casts: Casts? = figures.casts
	if casts then
		judgeCasts(figures, casts, lines, problems)
	else
		table.insert(problems, "P2 did not run")
	end

	local overlaps: Overlaps? = figures.overlaps
	if overlaps then
		judgeOverlaps(figures, overlaps, lines, problems)
	else
		table.insert(problems, "P7 did not run")
	end

	local battery: Battery? = figures.battery
	if battery then
		judgeBattery(figures, battery, lines, problems)
	else
		table.insert(problems, "P3 did not run")
	end

	return lines, problems
end

-- Waits a Heartbeat at a time until every clone has answered or ANSWER_WAIT runs out, the judge naming any silent
local function await(answered: (worker: number) -> boolean)
	Pool.within(ANSWER_WAIT, function (): boolean
		for worker: number = 1, WORKERS do
			if not answered(worker) then
				return false
			end
		end

		return true
	end)
end

-- P9: each clone's load attributes read, then the main thread's include list sent to every one to check
local function probeLoads(actors: { Actor }): Loads
	local include: { Instance } = Shared.collision.include or {}
	local figures: Loads = { loads = {}, checks = {}, failures = {} }

	for worker: number, actor: Actor in actors do
		local read: { [string]: unknown } = {}
		for _, attribute: string in LOADS do
			read[attribute] = actor:GetAttribute(attribute)
		end

		figures.loads[worker] = read
	end

	Pool.answering(actors, function (worker: number, same: boolean, own: number, received: number, failure: string?)
		if failure then
			figures.failures[worker] = failure
		else
			figures.checks[worker] = { same = same, own = own, received = received }
		end
	end, function (events: { BindableEvent })
		for worker: number, actor: Actor in actors do
			actor:SendMessage(Work.CHECK, events[worker], include)
		end

		await(function (worker: number): boolean
			return figures.checks[worker] ~= nil or figures.failures[worker] ~= nil
		end)
	end)

	return figures
end

-- A clone's P2 results put back together from its pieces, or why they don't make up the total it closed with
local function assemble(pieces: { Piece }, total: number): buffer | string
	local whole: buffer = buffer.create(total)
	local held: number = 0

	for _, entry: Piece in pieces do
		local length: number = buffer.len(entry.piece)
		if entry.offset < 0 or entry.offset + length > total then
			return `a piece of {length} B at {entry.offset} runs past the {total} B it closed with`
		end

		buffer.copy(whole, entry.offset, entry.piece)
		held += length
	end

	if held ~= total then
		return `its pieces held {held} of the {total} B it closed with`
	end

	return whole
end

--[[
    P2: the main thread's plan cast serially through its own casts and
    timed, then the same plan's inputs sent to every clone from one serial
    stretch, and each clone's pieces put back together and compared
--]]

local function probeCasts(
	actors: { Actor },
	casts: Collision,
	parts: { BasePart },
	slots: { BasePart },
	hull: Vector3
): Casts
	local radii: { number } = { SMALL_RADIUS, Shared.step.radius }
	local plan: buffer = Queries.plan(slots, hull, radii, PLAN_SEED)
	local index: { [Instance]: number } = Queries.indexOf(parts)

	local began: number = os.clock()
	local ours: buffer = Queries.cast(plan, hull, casts, index)
	local seconds: number = os.clock() - began

	local figures: Casts = {
		slots = #slots,
		parts = #parts,
		hash = Queries.hash(plan),
		seconds = seconds,
		tallies = Queries.compare(plan, ours, ours),
		casts = {},
		failures = {},
	}

	local pieces: { [number]: { Piece } } = {}
	local received: { [number]: number } = {}
	local closings: { [number]: Closing } = {}

	-- In once it has closed with an error, or every byte it closed with has come
	local function done(worker: number): boolean
		local closing: Closing? = closings[worker]

		return closing ~= nil and (closing.failure ~= nil or received[worker] == closing.total)
	end

	Pool.answering(actors, function (worker: number, offset: number, piece: buffer)
		local held: { Piece } = pieces[worker] or {}
		pieces[worker] = held
		table.insert(held, { offset = offset, piece = piece })
		received[worker] = (received[worker] or 0) + buffer.len(piece)
	end, function (pieceEvents: { BindableEvent })
		Pool.answering(actors, function (worker: number, total: number, hash: number, cast: number, failure: string?)
			closings[worker] = { total = total, hash = hash, seconds = cast, failure = failure }
		end, function (closingEvents: { BindableEvent })
			-- Each clone is sent its message in this one serial stretch, so all of them cast in one parallel phase
			for worker: number, actor: Actor in actors do
				actor:SendMessage(
					Work.CAST,
					pieceEvents[worker],
					closingEvents[worker],
					slots,
					parts,
					hull,
					radii,
					PLAN_SEED
				)
			end

			await(done)
		end)
	end)

	for worker: number, closing: Closing in closings do
		local failure: string? = closing.failure
		if failure then
			figures.failures[worker] = failure
			continue
		end

		local theirs: buffer | string = assemble(pieces[worker] or {}, closing.total)
		if type(theirs) == "string" then
			figures.failures[worker] = theirs
			continue
		end

		figures.casts[worker] =
			{ hash = closing.hash, seconds = closing.seconds, tallies = Queries.compare(plan, ours, theirs) }
	end

	return figures
end

--[[
    P7: the boxes answered through the main thread's own casts, then on
    every clone in its serial arm and in its desynchronized one, each
    clone's answers compared with the main thread's
--]]

local function probeOverlaps(actors: { Actor }, casts: Collision, slots: { BasePart }, hull: Vector3): Overlaps
	local boxes: buffer = Queries.boxes(slots, hull, BOXES, BOX_SEED)
	local ours: buffer = Queries.overlaps(boxes, casts.overlap)
	local own: OverlapTally = Queries.compareOverlaps(ours, ours)
	local figures: Overlaps = { boxes = own.boxes, overlapping = own.overlapping, arms = {} }

	for _, arm: { name: string, topic: string } in ARMS do
		local answers: { [number]: buffer } = {}
		local failures: { [number]: string } = {}

		Pool.answering(actors, function (worker: number, answered: buffer?, failure: string?)
			if failure then
				failures[worker] = failure
			elseif answered then
				answers[worker] = answered
			end
		end, function (events: { BindableEvent })
			for worker: number, actor: Actor in actors do
				actor:SendMessage(arm.topic, events[worker], slots, hull, BOXES, BOX_SEED)
			end

			await(function (worker: number): boolean
				return answers[worker] ~= nil or failures[worker] ~= nil
			end)
		end)

		local tallies: { [number]: OverlapTally } = {}
		for worker: number, answered: buffer in answers do
			tallies[worker] = Queries.compareOverlaps(ours, answered)
		end

		table.insert(figures.arms, { name = arm.name, tallies = tallies, failures = failures })
	end

	return figures
end

-- P3: the battery run on an anchored part of the main thread's own, unparented, then on every clone's
local function probeBattery(actors: { Actor }): Battery
	local part: Part = Instance.new("Part")
	part.Anchored = true

	local figures: Battery = { main = Builtins.run(part), results = {}, failures = {} }
	part:Destroy()

	Pool.answering(actors, function (worker: number, result: Result?, failure: string?)
		if failure then
			figures.failures[worker] = failure
		elseif result then
			figures.results[worker] = result
		end
	end, function (events: { BindableEvent })
		for worker: number, actor: Actor in actors do
			actor:SendMessage(Work.BATTERY, events[worker])
		end

		await(function (worker: number): boolean
			return figures.results[worker] ~= nil or figures.failures[worker] ~= nil
		end)
	end)

	return figures
end

-- Every probe in turn on the clones, through the main thread's own casts, each one's figures kept as it finishes
local function probe(actors: { Actor }, casts: Collision, figures: Figures)
	figures.loads = probeLoads(actors)

	local content: Instance? = Workspace:FindFirstChild(CONTENT)
	if not content then
		error(`Workspace.{CONTENT} is missing, so P2 has no parts to plan its queries beside`, 0)
	end

	local parts: { BasePart } = {}
	for _, descendant: Instance in content:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant :: BasePart)
		end
	end

	local slots: { BasePart } = Queries.slots(parts, SLOTS, SLOT_SEED)
	local hull: Vector3 = Vector3.new(SIDES * Shared.step.radius, Shared.step.standing, SIDES * Shared.step.radius)

	figures.casts = probeCasts(actors, casts, parts, slots, hull)
	figures.overlaps = probeOverlaps(actors, casts, slots, hull)
	figures.battery = probeBattery(actors)
end

--[[
    Runs the four probes on WORKERS clones of the step worker, its own casts
    built from the dev shared table and destroyed after, then judges them.
    The pool takes the clones and their events away whatever happened
--]]

function Step.run(): ({ string }, { string })
	local figures: Figures = { workers = WORKERS, wait = ANSWER_WAIT }

	figures.stopped = Pool.with(WORKERS, function (actors: { Actor }): string?
		local casts: Collision = Engine.casts(Shared.collision)
		local ran: boolean, thrown: unknown = pcall(probe, actors, casts, figures)
		casts.destroy()

		if not ran then
			error(thrown, 0)
		end

		return nil
	end, Template)

	return Step.judge(figures)
end

return Step
