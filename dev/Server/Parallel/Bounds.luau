--[[
    Probe P10 on clones of the step worker: the bounds query beside the
    exact check on P7's boxes and the loads' recorded ones, each clone's
    bounds answers compared with the main thread's, and the judge
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local Pool = require(ServerScriptService.Server.Parallel.Pool)
local Queries = require(ServerScriptService.Server.Parallel.Queries)
local Work = require(ServerScriptService.Server.Parallel.Work)

-- The Actor every step worker is cloned from, which never works itself
local Template = ServerScriptService.Server.Parallel.StepWorker

local WORKERS: number = require(ServerScriptService.Server.Config.Parallel).step.workers
local SLOTS: number = require(ServerScriptService.Server.Config.Parallel).step.slots
local BOXES: number = require(ServerScriptService.Server.Config.Parallel).step.boxes
local SLOT_SEED: number = require(ServerScriptService.Server.Config.Parallel).step.slotSeed
local BOX_SEED: number = require(ServerScriptService.Server.Config.Parallel).step.boxSeed
local PIECE_BYTES: number = require(ServerScriptService.Server.Config.Parallel).step.pieceBytes
local ANSWER_WAIT: number = require(ServerScriptService.Server.Config.Parallel).step.answerWait
local CONTENT: string = "TestContent" -- The folder under the Workspace whose BaseParts P7's boxes sit beside
local SIDES: number = 2 -- The hull spans the step's radius either side of its center
local BOX_BYTES: number = Queries.BOX_WIDTH * Queries.VALUE_BYTES
local ANSWER_BYTES: number = Queries.OVERLAP_WIDTH * Queries.VALUE_BYTES
local P7: string = "P7" -- The name of the source P7's boxes make
local PREFIX: string = "ParallelBounds" -- What each of the probe's lines begins with
local PERCENT: number = 100
local SHARE: string = "%.1f%%"
local POINT: string = "(%.3f, %.3f, %.3f)"
local NONE: string = "none" -- A clone's first difference when there is none
local LIST_SEPARATOR: string = ", "

type Collision = State.Collision
type OverlapTally = Queries.OverlapTally

-- One bot load's recorded boxes and its reads' counts, as the sampler gives them
export type Recording = {
	name: string, -- The load's name
	boxes: buffer, -- Queries.BOX_WIDTH f64s a box, the center then the size, recorded boxes only
	recorded: number, -- Boxes in the buffer
	dropped: number, -- Walking boxes past the cap, not kept
	reads: number, -- Bot reads that found a new tick
	walkers: number, -- Of those, walking with a changed position, so recorded plus dropped
	skipped: number, -- Ticks lost where a bot's tick moved on by more than one between reads
	failed: number, -- Bot reads that threw
}

-- One source's boxes as the main thread answered each, through the exact check and the bounds query
export type Source = {
	name: string,
	boxes: number,
	settled: number, -- Boxes the bounds query found nothing in
	inside: number, -- Boxes the exact check found something in
	unsound: number, -- Settled boxes the exact check found something in
	terrain: number, -- Boxes whose bounds query found Workspace.Terrain alone
	first: string?, -- The first unsound box's center and size
	recording: Recording?, -- The load's own counts, for a source it recorded
}

-- The probe's figures, a source kept once all its boxes are answered and the clones' left empty if never asked
export type Figures = {
	workers: number,
	wait: number, -- Seconds the clones' answers had
	sources: { Source },
	expected: buffer?, -- The main thread's bounds answers to every box each clone was sent, in the order sent
	answers: { [number]: buffer }, -- Each clone's answers to those boxes put back together, by its index
	failures: { [number]: string }, -- The error that stopped a clone, by its index
	stopped: string?, -- Why the run stopped short
}

-- One message's boxes: a count of P7's to rebuild, those sent, and the first one's place among every box
export type Message = {
	at: number,
	count: number,
	boxes: buffer,
}

-- A clone's answers to one message, and the first one's place
export type Piece = {
	at: number,
	answers: buffer,
}

local Bounds = {}

--[[
    One box's two answers counted into its source, from whether the exact
    check found something inside and the parts the bounds query found,
    Terrain told apart. Gives whether the bounds query found anything,
    which is the box's answer as a clone gives it
--]]

function Bounds.count(
	source: Source,
	center: vector,
	size: vector,
	inside: boolean,
	found: { BasePart },
	terrain: BasePart
): boolean
	source.boxes += 1
	if inside then
		source.inside += 1
	end

	if #found == 0 then
		source.settled += 1

		if inside then
			source.unsound += 1

			if not source.first then
				local spans: string = string.format(POINT, size.x, size.y, size.z)
				source.first = `center {string.format(POINT, center.x, center.y, center.z)}, size {spans}`
			end
		end

		return false
	end

	for _, part: BasePart in found do
		if part ~= terrain then
			return true
		end
	end

	source.terrain += 1

	return true
end

-- A source's line: its counts and settled share, then a load's own counts
local function sourceLine(source: Source): string
	local share: number = source.boxes > 0 and PERCENT * source.settled / source.boxes or 0
	local settled: string = `{source.settled} settled ({string.format(SHARE, share)})`
	local rest: string = `{source.inside} exact inside, {source.unsound} unsound, {source.terrain} Terrain-only`
	local counts: string = `{PREFIX} {source.name}: {source.boxes} boxes, {settled}, {rest}`

	local recording: Recording? = source.recording
	if not recording then
		return counts
	end

	local reads: string = `{recording.reads} reads, {recording.walkers} walkers, {recording.dropped} dropped`

	return `{counts}; {reads}, {recording.skipped} skipped, {recording.failed} failed`
end

--[[
    The figures turned into a line a source and a line a clone, and every
    problem found: an unsound box or no boxes in a source, and a clone
    whose answers differ box by box from the main thread's, that failed or
    that stayed silent. The settled share is printed and never judged
--]]

function Bounds.judge(figures: Figures): ({ string }, { string })
	local lines: { string } = {}
	local problems: { string } = {}

	local stopped: string? = figures.stopped
	if stopped then
		table.insert(problems, `stopped short: {stopped}`)
	end

	for _, source: Source in figures.sources do
		table.insert(lines, sourceLine(source))

		if source.boxes == 0 then
			table.insert(problems, `{source.name}: no boxes`)
		end

		if source.unsound > 0 then
			local share: string = `{source.unsound} of {source.boxes} boxes`
			table.insert(problems, `{source.name}: {share} unsound, the first at {source.first}`)
		end
	end

	local expected: buffer? = figures.expected
	local silent: { string } = {}

	for worker: number = 1, figures.workers do
		local answers: buffer? = figures.answers[worker]
		local failure: string? = figures.failures[worker]

		if expected and answers then
			local tally: OverlapTally = Queries.compareOverlaps(expected, answers)
			local first: string = tally.first or NONE
			local counts: string = `{tally.boxes} boxes compared, {tally.differing} differing`
			table.insert(lines, `{PREFIX} clone {worker}: {counts}, first difference {first}`)

			if tally.differing > 0 then
				local share: string = `{tally.differing} of {tally.boxes} boxes`
				table.insert(problems, `clone {worker}: {share} answered otherwise than the main thread, first {first}`)
			end
		elseif failure then
			table.insert(lines, `{PREFIX} clone {worker}: failed: {failure}`)
			table.insert(problems, `clone {worker}: failed: {failure}`)
		else
			table.insert(lines, `{PREFIX} clone {worker}: no answer within {figures.wait} s`)
			table.insert(silent, `{worker}`)
		end
	end

	if #silent > 0 then
		local noun: string = #silent == 1 and "clone" or "clones"
		table.insert(problems, `no answer from {noun} {table.concat(silent, LIST_SEPARATOR)} within {figures.wait} s`)
	end

	return lines, problems
end

-- The bounds query's filter, made as the exact check's is: the include list's parts with CanCollide on, or every part
local function filter(include: { Instance }?): OverlapParams
	local params: OverlapParams = OverlapParams.new()
	params.RespectCanCollide = true

	if include then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
	end

	return params
end

--[[
    Every box of a source through the exact check and the bounds query on
    the main thread, each counted into the source, giving the bounds
    query's answers, 1 for a box it found anything in
--]]

local function answer(source: Source, boxes: buffer, casts: Collision, params: OverlapParams): buffer
	return Queries.overlaps(boxes, function (center: vector, size: vector): boolean
		local inside: boolean = casts.overlap(center, size)
		local box: CFrame = CFrame.new(center.x, center.y, center.z)
		local found: { BasePart } = Workspace:GetPartBoundsInBox(box, Vector3.new(size.x, size.y, size.z), params)

		return Bounds.count(source, center, size, inside, found, Workspace.Terrain)
	end)
end

local function newSource(name: string, recording: Recording?): Source
	return { name = name, boxes = 0, settled = 0, inside = 0, unsound = 0, terrain = 0, recording = recording }
end

-- The first that many records of that many bytes from each stream, joined in order
local function joined(streams: { buffer }, counts: { number }, width: number): buffer
	local total: number = 0
	for _, count: number in counts do
		total += count
	end

	local whole: buffer = buffer.create(total * width)
	local at: number = 0
	for index: number, stream: buffer in streams do
		local length: number = counts[index] * width
		buffer.copy(whole, at, stream, 0, length)
		at += length
	end

	return whole
end

--[[
    The messages each clone is sent: the first rebuilds P7's boxes and
    carries the first of the recorded boxes after them, and the rest carry
    the remainder, each at most PIECE_BYTES of boxes
--]]

function Bounds.messages(sent: buffer): { Message }
	local most: number = math.max(1, PIECE_BYTES // BOX_BYTES) * BOX_BYTES
	local total: number = buffer.len(sent)
	local messages: { Message } = {}
	local offset: number = 0

	repeat
		local length: number = math.min(most, total - offset)
		local piece: buffer = buffer.create(length)
		buffer.copy(piece, 0, sent, offset, length)

		local first: boolean = offset == 0
		table.insert(messages, {
			at = first and 0 or BOXES + offset // BOX_BYTES,
			count = first and BOXES or 0,
			boxes = piece,
		})

		offset += length
	until offset >= total

	return messages
end

--[[
    A clone's answers to its messages put back at their boxes, in whatever
    order they came, or why they don't cover the boxes it was sent
--]]

function Bounds.assemble(pieces: { Piece }, boxes: number): buffer | string
	local whole: buffer = buffer.create(boxes * ANSWER_BYTES)
	local held: number = 0

	for _, piece: Piece in pieces do
		local offset: number = piece.at * ANSWER_BYTES
		local length: number = buffer.len(piece.answers)
		if offset < 0 or offset + length > buffer.len(whole) then
			local answered: string = `{length // ANSWER_BYTES} answers from box {piece.at + 1}`
			return `{answered} run past the {boxes} boxes it was sent`
		end

		buffer.copy(whole, offset, piece.answers)
		held += length
	end

	if held ~= buffer.len(whole) then
		return `its answers held {held // ANSWER_BYTES} of the {boxes} boxes it was sent`
	end

	return whole
end

--[[
    The parallel check: every message sent to every clone from one serial
    stretch, P7's boxes rebuilt on each clone, and each clone's answers put
    back together once it has answered every message, or its error kept
--]]

local function check(actors: { Actor }, slots: { BasePart }, hull: Vector3, sent: buffer, figures: Figures)
	local messages: { Message } = Bounds.messages(sent)
	local boxes: number = BOXES + buffer.len(sent) // BOX_BYTES
	local pieces: { [number]: { Piece } } = {}

	-- In once it has failed or answered every message
	local function done(worker: number): boolean
		local held: { Piece }? = pieces[worker]

		return figures.failures[worker] ~= nil or (held ~= nil and #held == #messages)
	end

	Pool.answering(actors, function (worker: number, at: number, answers: buffer?, failure: string?)
		if failure then
			figures.failures[worker] = failure
		elseif answers then
			local held: { Piece } = pieces[worker] or {}
			pieces[worker] = held
			table.insert(held, { at = at, answers = answers })
		end
	end, function (events: { BindableEvent })
		for worker: number, actor: Actor in actors do
			for _, message: Message in messages do
				actor:SendMessage(
					Work.BOUNDS,
					events[worker],
					message.at,
					slots,
					hull,
					message.count,
					BOX_SEED,
					message.boxes
				)
			end
		end

		-- A Heartbeat at a time until every clone is in or ANSWER_WAIT runs out, the judge naming any silent
		Pool.within(ANSWER_WAIT, function (): boolean
			for worker: number = 1, #actors do
				if not done(worker) then
					return false
				end
			end

			return true
		end)
	end)

	for worker: number, held: { Piece } in pieces do
		if figures.failures[worker] == nil and #held == #messages then
			local whole: buffer | string = Bounds.assemble(held, boxes)
			if type(whole) == "string" then
				figures.failures[worker] = whole
			else
				figures.answers[worker] = whole
			end
		end
	end
end

--[[
    P7's boxes and each recording's through the main thread's two queries,
    each source kept as it finishes, then the first boxes of each recording
    behind P7's through every clone's bounds query
--]]

local function probe(
	actors: { Actor },
	casts: Collision,
	recordings: { Recording },
	parallelBoxes: number,
	figures: Figures
)
	local content: Instance? = Workspace:FindFirstChild(CONTENT)
	if not content then
		error(`Workspace.{CONTENT} is missing, so P7's boxes have no parts to sit beside`, 0)
	end

	local parts: { BasePart } = {}
	for _, descendant: Instance in content:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant :: BasePart)
		end
	end

	local slots: { BasePart } = Queries.slots(parts, SLOTS, SLOT_SEED)
	local hull: Vector3 = Vector3.new(SIDES * Shared.step.radius, Shared.step.standing, SIDES * Shared.step.radius)
	local params: OverlapParams = filter(Shared.collision.include)

	local p7: Source = newSource(P7, nil)
	local answered: { buffer } = { answer(p7, Queries.boxes(slots, hull, BOXES, BOX_SEED), casts, params) }
	local answeredCounts: { number } = { p7.boxes }
	table.insert(figures.sources, p7)

	local recorded: { buffer } = {}
	local recordedCounts: { number } = {}

	for _, recording: Recording in recordings do
		local bytes: number = buffer.len(recording.boxes)
		if bytes ~= recording.recorded * BOX_BYTES then
			local said: string = `{recording.recorded} boxes of {BOX_BYTES} B it recorded`
			error(`{recording.name}'s boxes are {bytes} B, not the {said}`, 0)
		end

		local source: Source = newSource(recording.name, recording)
		local answers: buffer = answer(source, recording.boxes, casts, params)
		local first: number = math.min(parallelBoxes, recording.recorded)
		table.insert(figures.sources, source)

		table.insert(answered, answers)
		table.insert(answeredCounts, first)
		table.insert(recorded, recording.boxes)
		table.insert(recordedCounts, first)
	end

	figures.expected = joined(answered, answeredCounts, ANSWER_BYTES)
	check(actors, slots, hull, joined(recorded, recordedCounts, BOX_BYTES), figures)
end

--[[
    Runs P10 on WORKERS clones of the step worker with the loads' recorded
    boxes, each clone sent the first parallelBoxes of each, the exact
    check's casts built from the dev shared table and destroyed after,
    then judges it. The pool takes the clones away whatever happened
--]]

function Bounds.run(recordings: { Recording }, parallelBoxes: number): ({ string }, { string })
	if parallelBoxes ~= parallelBoxes // 1 or parallelBoxes < 0 then
		error(`parallelBoxes must be a whole number from 0, and got {parallelBoxes}`)
	end

	local figures: Figures = { workers = WORKERS, wait = ANSWER_WAIT, sources = {}, answers = {}, failures = {} }

	figures.stopped = Pool.with(WORKERS, function (actors: { Actor }): string?
		local casts: Collision = Engine.casts(Shared.collision)
		local ran: boolean, thrown: unknown = pcall(probe, actors, casts, recordings, parallelBoxes, figures)
		casts.destroy()

		if not ran then
			error(thrown, 0)
		end

		return nil
	end, Template)

	return Bounds.judge(figures)
end

return Bounds
