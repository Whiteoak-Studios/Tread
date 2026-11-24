--[[
    The relay's layouts across an Actor's boundary: the hand-in every worker
    shares, each worker's own, its result with the copy of each view it ran
    and its clocks' order, every writer the exact inverse of its reader
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Parent.Codec.Block)
local Constants = require(script.Parent.Parent.Parent.Constants)
local Turn = require(script.Parent.Turn)

local SLOTS: number = Constants.SLOTS
local RECORD_BYTES: number = Constants.RECORD_BYTES
local MAX_LOOK: number = Constants.MAX_LOOK
local MAX_HELD: number = Constants.MAX_HELD
local FOOTSTEP_BYTES: number = Constants.FOOTSTEP_BYTES
local DEPTH: number = Constants.CHANGE_DEPTH -- The history's planes, one a run
local BITS: number = 8 -- A byte's, each one slot's or one walk place's mark in a row
local ROW_BYTES: number = SLOTS // BITS -- A viewer's row of anti-ESP's answers, a bit a slot, as AntiEsp.answers lays it
local U16_TOP: number = 2 ^ 16 - 1 -- The most a u16 count holds, and a u16 slot's mark for none
local NO_SLOT: number = U16_TOP
local ID_BYTES: number = 4 -- A key's id, a u32
local START_BYTES: number = 2 ^ 16 -- A result writer's first buffer, doubled whenever a run's result needs more
local CALLS_START: number = 64 -- The calls a log holds before it doubles

-- The flags a view's copy keeps, Turn's own
local SENT: number = Turn.SENT
local OWN: number = Turn.OWN
local WITHHELD: number = Turn.WITHHELD

-- The shared hand-in: its header, then the run's bands, the looks and Invisible marks changed between runs, every
-- present body in walk order, the held items this run's walk changed, its footsteps and the ids of the keys a sink
-- observes
local SHARED_BYTES: number = 35
local TUNING_BYTES: number = 20 -- bands u8, flags u8, crowd size u16, crowd rate f64, crowd floor f64
local BAND_BYTES: number = 16 -- aim f64, floor f64
local EDGE_BYTES: number = 16 -- enter squared f64, leave squared f64
local LOOK_BYTES: number = 7 -- slot u16, look life u8, version u16, Invisible u8, length u8, then the look
local BODY_BYTES: number = 54 -- slot u16, life u8, kind u8, flags u8, place 3 f32, facing f64, changed u32, record,
-- then anti-ESP's kind u8 and team f64
local HELD_BYTES: number = 5 -- slot u16, version u16, length u8, then the held item
local STEP_BYTES: number = 15 + FOOTSTEP_BYTES -- slot u16, kind u8, place 3 f32, then the entry
local UNPARKED: number = 2 ^ 0 -- A body's flag: in the states and not Parked

-- A worker's own hand-in: its calls in call order, then its viewers in the front's order, each with no target followed
-- by its two rows of anti-ESP's answers, visible then quiet
local OWN_BYTES: number = 7 -- calls u32, viewers u16, flags u8
local RESEND: number = 2 ^ 0 -- Its flag: the worker drops its shadows first, so each view it runs goes whole
local CALL_BYTES: number = 15 -- kind u8, id u32, slot u16, value f64
local HAND_BYTES: number = 57 -- id u32, flags u8, slot u16, target u32, place 3 f32, look 3 f32, acknowledged u16,
-- received u16, sequence u16, traffic f64, team f64
local HAS_SLOT: number = 2 ^ 0
local HAS_TARGET: number = 2 ^ 1
local HAS_LOOK: number = 2 ^ 2
local BACK: number = 2 ^ 3
local ZOOMED: number = 2 ^ 4
local MISSED: number = 2 ^ 5

-- A worker's result: its header, each turn's section, the changes to each view it ran, each watcher's answer and the
-- text of a turn that threw
local RESULT_BYTES: number = 40
local SECTION_BYTES: number = 7 -- length u32, place u16, recipients u8, before the recipients' ids, its row of asks,
-- its row of marks and its events
local VIEW_BYTES: number = 9 -- id u32, own u16, withheld u8, facts u16, before the facts
local FACT_BYTES: number = 6 -- slot u16, marks u8, life u8, kind u8, withheld life u8
local CHANGE_BYTES: number = 4 -- tracked index u16, slot u16
local FACT_SENT: number = 2 ^ 0
local FACT_OWN: number = 2 ^ 1
local FACT_WITHHELD: number = 2 ^ 2

-- The calls a front queues for a worker's views between runs, each taking a slot, a value or both
local SHOT_NEAR: number = 1 -- slot, and the relay tick through which the raised rate lasts
local REVEAL: number = 2 -- slot
local REVEAL_ALL: number = 3 -- the run its records' floor starts at
local SET_DISTANCE: number = 4 -- the render distance
local REMOVE: number = 5

-- The events of a turn, in the order its ports were called
local SEND: number = 1
local RELAYED: number = 2 -- A tap on the block just sent, its bytes that block's
local RELAYED_BYTES: number = 3 -- A tap carrying bytes of its own, which its reader hands on as RELAYED
local HEARD: number = 4
local WITHHELD_SEND: number = 5
local WITHHELD_TAP: number = 6 -- A tap on the withheld block just sent

-- A watcher's answer from Turn.watch
local UNWATCHED: number = 0 -- Its target runs no turn here
local OVERFULL: number = 1
local WATCHED: number = 2

-- The sections a worker's clocks time with relay.clocks on, an f64 each in this order: its turns' parts summed over
-- them, as Turn.clocks lays them out, then its run's own parts
local CLOCKS: { string } = {
	"head",
	"gather",
	"measure",
	"settle",
	"schedule",
	"place",
	"send",
	"unpack",
	"bodies",
	"grid",
	"ready",
	"turns",
	"views",
	"pack",
}

local CLOCK_AT: { [string]: number } = {} -- Each section's offset in a worker's clocks
for index: number, name: string in CLOCKS do
	CLOCK_AT[name] = (index - 1) * 8
end

type Steps = Turn.Steps
type Tuning = Turn.Tuning
type View = Turn.View
type World = Turn.World

-- What the shared hand-in carries beside the world's own facts, which the front fills and a worker reads back
export type Shared = {
	run: number,
	tick: number, -- Unwrapped
	elapsed: number,
	wire: number,
	tune: Tuning, -- The run's bands, the front's own as it writes them, and a reader's lists reused run to run
	places: number, -- The bodies the front's walk filed this run, the places of world.walk from 1
	looks: { number }, -- The slots whose look or Invisible changed since the last run, for lookCount
	lookCount: number,
	helds: { number }, -- And those whose held item this run's walk changed, for heldCount
	heldCount: number,
	observing: boolean, -- Whether any sink observes anything
	observed: { number }, -- The ids of the keys a sink observes the blocks of, for observedCount
	observedCount: number,
	kinds: buffer, -- u8 by slot: anti-ESP's kind for each, as AntiEsp.answers gives it, read for present slots
	teams: buffer, -- f64 by slot: and its team, NaN for none
}

-- The calls queued for one worker's views, in call order, which the front empties once a hand-in carries them
export type Calls = {
	data: buffer,
	count: number,
}

-- One viewer as a worker is handed it, beside its Turn.Viewer's own fields
export type Hand = {
	id: number,
	slot: number?,
	target: number?, -- The id of the viewer it spectates
	position: vector,
	look: vector?,
	acknowledged: number,
	received: number,
	sequence: number, -- latest for a watcher, the back of a viewer back from a spectate, 0 otherwise
	back: boolean, -- Whether a viewer with no target is back from a spectate this run, its back in sequence
	zoomed: boolean, -- Whether its players go at the nearest band's rates wherever they stand
	missed: boolean, -- Whether the relay's budget left a viewer with no target in the run before
	traffic: number, -- Volt's count read at dispatch, for a viewer with no target
	team: number, -- Anti-ESP's team for its own slot, NaN for none
	row: number, -- Its visible row's offset in the buffer holding it: the export's when written, where its quiet row
	-- has the same offset in the quiet buffer, and the hand-in's when read, its quiet row ROW_BYTES past it
}

-- A copy of a view's withheld set
export type Withheld = {
	flags: buffer, -- u8 by slot: Turn.WITHHELD for a slot withheld from it
	lives: buffer, -- u8 by slot: the life a withheld slot's stretch belongs to
}

-- What the front keeps of a view a worker hosts: what isSent, viewersOf and keyframe read of it
export type Copy = {
	own: number?,
	tracked: { number }, -- In the view's own order
	flags: buffer, -- u16 by slot: Turn.SENT and Turn.OWN as the view holds them
	generations: buffer, -- u8 by slot: the life of a slot sent or of its own, 0 for any other
	kinds: buffer, -- u8 by slot: the kind code a slot sent was revealed as, 0 for any other
	withheld: Withheld?, -- Made the first time the view is watched
}

-- A worker's result being written, its buffer kept across runs
export type Writer = {
	data: buffer,
	at: number,
	places: number, -- This run's walk places, which each turn's rows of asks and marks hold a bit for
	rowBytes: number,
	turns: number,
	section: number, -- Where the turn being written starts
	asks: number, -- Where its row of asks starts
	marks: number, -- And its row of marks, the asks the front hands anti-ESP as only stamping their pairs
	events: number, -- Where its count of events is
	views: number,
	viewsStart: number, -- Where the first view's changes start
	answers: buffer, -- Each watcher's answer, in list order
	answerCount: number,
}

-- A worker's result being read by the front, each turn and view in order
export type Reader = {
	data: buffer,
	turns: number,
	views: number,
	answers: number,
	places: number,
	sent: number, -- The records the band ticks placed, those cut, the bodies gathered and the candidates held outside a
	-- crowd cap, this run
	cut: number,
	visited: number,
	rest: number,
	failed: number, -- The place from 1 in the worker's list of the viewer whose turn threw, 0 for none
	failure: string, -- And its error's text
	place: number, -- The place from 1 in the worker's list of the viewer whose turn was read last
	recipients: { number }, -- Its recipients' ids, the viewer first, then each watcher by bit
	recipientCount: number,
	block: buffer, -- The bytes of the newest block or withheld block read, valid until the next event
	sequence: number, -- The newest heard sequence read
	tap: Block.Block, -- The newest tap's records, each at its slot's record in the front's own records
	_at: number, -- Where the next turn starts
	_turn: number, -- The turns read
	_asks: number,
	_marks: number,
	_event: number,
	_left: number, -- The events of the turn still to read
	_view: number, -- The views read
	_viewAt: number,
	_viewEnd: number,
	_answersAt: number,
}

-- Each block's bytes as the front hands them on, one buffer a length, reused
local Outgoing: { [number]: buffer } = {}

local Wire = {
	ROW_BYTES = ROW_BYTES,
	SHOT_NEAR = SHOT_NEAR,
	REVEAL = REVEAL,
	REVEAL_ALL = REVEAL_ALL,
	SET_DISTANCE = SET_DISTANCE,
	REMOVE = REMOVE,
	SEND = SEND,
	RELAYED = RELAYED,
	HEARD = HEARD,
	WITHHELD = WITHHELD_SEND,
	WITHHELD_TAP = WITHHELD_TAP,
	CLOCKS = CLOCKS,
	CLOCK_AT = CLOCK_AT,
	CLOCK_BYTES = #CLOCKS * 8, -- A worker's clocks' length
}

-- Errors naming a count past the u16 its field holds
local function bounded(count: number, what: string)
	if count > U16_TOP then
		error(`A relay hand-in or result holds at most {U16_TOP} {what}, not {count}`)
	end
end

-- Bands with none in them, for the front to work its own out into or a reader to fill
function Wire.tuning(): Tuning
	return {
		bands = 0,
		flags = 0,
		crowdSize = 0,
		crowdRate = 0,
		crowdFloor = 0,
		aims = {},
		floors = {},
		enters = {},
		leaves = {},
	}
end

--[[
    The shared hand-in for a run, from the world the front's walk of the
    states filled and what shared gives: the run's bands, the looks and
    Invisible marks changed since the last run, every present body in walk
    order with anti-ESP's kind and team for it, the held items the walk
    changed, the footsteps and the keys a sink observes
--]]

function Wire.writeShared(world: World, shared: Shared): buffer
	local places: number = shared.places
	local lookCount: number = shared.lookCount
	local heldCount: number = shared.heldCount
	local observedCount: number = shared.observedCount
	local steps: Steps = world.steps
	local stepCount: number = steps.count
	local lookLengths: buffer = world.lookLengths
	local heldLengths: buffer = world.heldLengths
	local tune: Tuning = shared.tune
	local bands: number = tune.bands
	local edges: number = math.max(bands - 1, 0)

	bounded(math.max(places, lookCount, heldCount, observedCount), "places, marks or observed keys")

	local size: number = SHARED_BYTES + places * BODY_BYTES + stepCount * STEP_BYTES + observedCount * ID_BYTES
	size += TUNING_BYTES + bands * BAND_BYTES + edges * EDGE_BYTES
	for index: number = 1, lookCount do
		size += LOOK_BYTES + buffer.readu8(lookLengths, shared.looks[index])
	end

	for index: number = 1, heldCount do
		size += HELD_BYTES + buffer.readu8(heldLengths, shared.helds[index])
	end

	local data: buffer = buffer.create(size)
	local run: number = shared.run
	buffer.writeu32(data, 0, run)
	buffer.writef64(data, 4, shared.tick)
	buffer.writef64(data, 12, shared.elapsed)
	buffer.writeu16(data, 20, shared.wire)
	buffer.writeu16(data, 22, places)
	buffer.writeu16(data, 24, lookCount)
	buffer.writeu16(data, 26, heldCount)
	buffer.writeu32(data, 28, stepCount)
	buffer.writeu8(data, 32, shared.observing and 1 or 0)
	buffer.writeu16(data, 33, observedCount)

	buffer.writeu8(data, SHARED_BYTES, bands)
	buffer.writeu8(data, SHARED_BYTES + 1, tune.flags)
	buffer.writeu16(data, SHARED_BYTES + 2, tune.crowdSize)
	buffer.writef64(data, SHARED_BYTES + 4, tune.crowdRate)
	buffer.writef64(data, SHARED_BYTES + 12, tune.crowdFloor)

	local at: number = SHARED_BYTES + TUNING_BYTES
	for band: number = 1, bands do
		buffer.writef64(data, at, tune.aims[band])
		buffer.writef64(data, at + 8, tune.floors[band])
		at += BAND_BYTES
	end

	for edge: number = 1, edges do
		buffer.writef64(data, at, tune.enters[edge])
		buffer.writef64(data, at + 8, tune.leaves[edge])
		at += EDGE_BYTES
	end

	local looks: buffer = world.looks
	local lookLives: buffer = world.lookLives
	local lookVersions: buffer = world.lookVersions
	local invisible: buffer = world.invisible

	for index: number = 1, lookCount do
		local slot: number = shared.looks[index]
		local length: number = buffer.readu8(lookLengths, slot)

		buffer.writeu16(data, at, slot)
		buffer.writeu8(data, at + 2, buffer.readu8(lookLives, slot))
		buffer.writeu16(data, at + 3, buffer.readu16(lookVersions, slot * 2))
		buffer.writeu8(data, at + 5, buffer.readu8(invisible, slot))
		buffer.writeu8(data, at + 6, length)
		buffer.copy(data, at + LOOK_BYTES, looks, slot * MAX_LOOK, length)
		at += LOOK_BYTES + length
	end

	local walk: buffer = world.walk
	local generations: buffer = world.generations
	local kinds: buffer = world.kinds
	local unparked: buffer = world.unparked
	local positions: { vector } = world.positions
	local facings: buffer = world.facings
	local changed: buffer = world.changed
	local records: buffer = world.records
	local antiKinds: buffer = shared.kinds
	local antiTeams: buffer = shared.teams

	for place: number = 1, places do
		local slot: number = buffer.readu16(walk, place * 2)
		local position: vector = positions[slot + 1]
		local flags: number = 0
		if buffer.readu32(unparked, slot * 4) == run then
			flags = UNPARKED
		end

		buffer.writeu16(data, at, slot)
		buffer.writeu8(data, at + 2, buffer.readu8(generations, slot))
		buffer.writeu8(data, at + 3, buffer.readu8(kinds, slot))
		buffer.writeu8(data, at + 4, flags)
		buffer.writef32(data, at + 5, position.x)
		buffer.writef32(data, at + 9, position.y)
		buffer.writef32(data, at + 13, position.z)
		buffer.copy(data, at + 17, facings, slot * 8, 8)
		buffer.writeu32(data, at + 25, buffer.readu32(changed, slot * 4))
		buffer.copy(data, at + 29, records, slot * RECORD_BYTES, RECORD_BYTES)
		buffer.writeu8(data, at + 45, buffer.readu8(antiKinds, slot))
		buffer.copy(data, at + 46, antiTeams, slot * 8, 8)
		at += BODY_BYTES
	end

	local helds: buffer = world.helds
	local heldVersions: buffer = world.heldVersions

	for index: number = 1, heldCount do
		local slot: number = shared.helds[index]
		local length: number = buffer.readu8(heldLengths, slot)

		buffer.writeu16(data, at, slot)
		buffer.writeu16(data, at + 2, buffer.readu16(heldVersions, slot * 2))
		buffer.writeu8(data, at + 4, length)
		buffer.copy(data, at + HELD_BYTES, helds, slot * MAX_HELD, length)
		at += HELD_BYTES + length
	end

	local stepSlots: buffer = steps.slots
	local stepKinds: buffer = steps.kinds
	local stepPlaces: { vector } = steps.places
	local stepData: buffer = steps.data

	for index: number = 0, stepCount - 1 do
		local place: vector = stepPlaces[index + 1]

		buffer.writeu16(data, at, buffer.readu16(stepSlots, index * 2))
		buffer.writeu8(data, at + 2, buffer.readu8(stepKinds, index))
		buffer.writef32(data, at + 3, place.x)
		buffer.writef32(data, at + 7, place.y)
		buffer.writef32(data, at + 11, place.z)
		buffer.copy(data, at + 15, stepData, index * FOOTSTEP_BYTES, FOOTSTEP_BYTES)
		at += STEP_BYTES
	end

	for index: number = 1, observedCount do
		buffer.writeu32(data, at, shared.observed[index])
		at += ID_BYTES
	end

	return data
end

-- Cuts a list a reader refills back to its first count entries
local function trim(list: { number }, count: number)
	for index: number = #list, count + 1, -1 do
		list[index] = nil
	end
end

--[[
    Reads a shared hand-in's header and the run's bands into into, the
    bands' lists refilled in place, and the looks and Invisible marks it
    carries into the world, as setLook and setInvisible left the front's,
    giving where its bodies start
--]]

function Wire.readLooks(data: buffer, world: World, into: Shared): number
	into.run = buffer.readu32(data, 0)
	into.tick = buffer.readf64(data, 4)
	into.elapsed = buffer.readf64(data, 12)
	into.wire = buffer.readu16(data, 20)
	into.places = buffer.readu16(data, 22)
	into.lookCount = buffer.readu16(data, 24)
	into.heldCount = buffer.readu16(data, 26)
	into.observing = buffer.readu8(data, 32) ~= 0
	into.observedCount = buffer.readu16(data, 33)

	local tune: Tuning = into.tune
	local bands: number = buffer.readu8(data, SHARED_BYTES)
	local edges: number = math.max(bands - 1, 0)
	tune.bands = bands
	tune.flags = buffer.readu8(data, SHARED_BYTES + 1)
	tune.crowdSize = buffer.readu16(data, SHARED_BYTES + 2)
	tune.crowdRate = buffer.readf64(data, SHARED_BYTES + 4)
	tune.crowdFloor = buffer.readf64(data, SHARED_BYTES + 12)

	local at: number = SHARED_BYTES + TUNING_BYTES
	for band: number = 1, bands do
		tune.aims[band] = buffer.readf64(data, at)
		tune.floors[band] = buffer.readf64(data, at + 8)
		at += BAND_BYTES
	end

	for edge: number = 1, edges do
		tune.enters[edge] = buffer.readf64(data, at)
		tune.leaves[edge] = buffer.readf64(data, at + 8)
		at += EDGE_BYTES
	end

	trim(tune.aims, bands)
	trim(tune.floors, bands)
	trim(tune.enters, edges)
	trim(tune.leaves, edges)

	local looks: buffer = world.looks
	local lookLengths: buffer = world.lookLengths
	local lookLives: buffer = world.lookLives
	local lookVersions: buffer = world.lookVersions
	local invisible: buffer = world.invisible
	local marked: { number } = into.looks

	for index: number = 1, into.lookCount do
		local slot: number = buffer.readu16(data, at)
		local length: number = buffer.readu8(data, at + 6)

		buffer.writeu8(lookLives, slot, buffer.readu8(data, at + 2))
		buffer.writeu16(lookVersions, slot * 2, buffer.readu16(data, at + 3))
		buffer.writeu8(invisible, slot, buffer.readu8(data, at + 5))
		buffer.writeu8(lookLengths, slot, length)
		buffer.copy(looks, slot * MAX_LOOK, data, at + LOOK_BYTES, length)
		marked[index] = slot
		at += LOOK_BYTES + length
	end

	return at
end

-- Makes room for count footsteps in a run's buffers, which the walk fills afresh every run
local function stepRoom(steps: Steps, count: number)
	if count <= steps.capacity then
		return
	end

	local capacity: number = math.max(count, steps.capacity * 2)
	steps.capacity = capacity
	steps.slots = buffer.create(capacity * 2)
	steps.kinds = buffer.create(capacity)
	steps.data = buffer.create(capacity * FOOTSTEP_BYTES)
end

--[[
    Reads the rest of a shared hand-in from at into the world, as the front's
    walk of the states filled its own: each present body's facts, its record
    in the run's plane of the history while records go as changes, and its
    place in the walk; the held items; the footsteps; and into into, anti-ESP's
    kind and team for each present body and the observed keys' ids
--]]

function Wire.readBodies(data: buffer, at: number, world: World, into: Shared, changes: boolean)
	local run: number = into.run
	local plane: number = (run % DEPTH) * SLOTS
	local present: buffer = world.present
	local generations: buffer = world.generations
	local kinds: buffer = world.kinds
	local unparked: buffer = world.unparked
	local positions: { vector } = world.positions
	local facings: buffer = world.facings
	local changed: buffer = world.changed
	local records: buffer = world.records
	local history: buffer = world.history
	local walk: buffer = world.walk
	local antiKinds: buffer = into.kinds
	local antiTeams: buffer = into.teams

	for place: number = 1, into.places do
		local slot: number = buffer.readu16(data, at)

		buffer.writeu32(present, slot * 4, run)
		buffer.writeu8(generations, slot, buffer.readu8(data, at + 2))
		buffer.writeu8(kinds, slot, buffer.readu8(data, at + 3))
		if bit32.btest(buffer.readu8(data, at + 4), UNPARKED) then
			buffer.writeu32(unparked, slot * 4, run)
		end

		positions[slot + 1] =
			vector.create(buffer.readf32(data, at + 5), buffer.readf32(data, at + 9), buffer.readf32(data, at + 13))
		buffer.copy(facings, slot * 8, data, at + 17, 8)
		buffer.writeu32(changed, slot * 4, buffer.readu32(data, at + 25))
		buffer.copy(records, slot * RECORD_BYTES, data, at + 29, RECORD_BYTES)
		if changes then
			buffer.copy(history, (plane + slot) * RECORD_BYTES, data, at + 29, RECORD_BYTES)
		end

		buffer.writeu16(walk, place * 2, slot)
		buffer.writeu8(antiKinds, slot, buffer.readu8(data, at + 45))
		buffer.copy(antiTeams, slot * 8, data, at + 46, 8)
		at += BODY_BYTES
	end

	local helds: buffer = world.helds
	local heldLengths: buffer = world.heldLengths
	local heldVersions: buffer = world.heldVersions
	local marked: { number } = into.helds

	for index: number = 1, into.heldCount do
		local slot: number = buffer.readu16(data, at)
		local length: number = buffer.readu8(data, at + 4)

		buffer.writeu16(heldVersions, slot * 2, buffer.readu16(data, at + 2))
		buffer.writeu8(heldLengths, slot, length)
		buffer.copy(helds, slot * MAX_HELD, data, at + HELD_BYTES, length)
		marked[index] = slot
		at += HELD_BYTES + length
	end

	local steps: Steps = world.steps
	local stepCount: number = buffer.readu32(data, 28)
	stepRoom(steps, stepCount)
	steps.count = stepCount

	local stepSlots: buffer = steps.slots
	local stepKinds: buffer = steps.kinds
	local stepPlaces: { vector } = steps.places
	local stepData: buffer = steps.data

	for index: number = 0, stepCount - 1 do
		buffer.writeu16(stepSlots, index * 2, buffer.readu16(data, at))
		buffer.writeu8(stepKinds, index, buffer.readu8(data, at + 2))
		stepPlaces[index + 1] =
			vector.create(buffer.readf32(data, at + 3), buffer.readf32(data, at + 7), buffer.readf32(data, at + 11))
		buffer.copy(stepData, index * FOOTSTEP_BYTES, data, at + 15, FOOTSTEP_BYTES)
		at += STEP_BYTES
	end

	local observed: { number } = into.observed
	for index: number = 1, into.observedCount do
		observed[index] = buffer.readu32(data, at)
		at += ID_BYTES
	end
end

--[[
    An empty log of the calls queued for one worker's views
--]]

function Wire.calls(): Calls
	return { data = buffer.create(CALLS_START * CALL_BYTES), count = 0 }
end

--[[
    Queues one call for a worker's view, keyed by its id: SHOT_NEAR with
    its shooter's slot and the relay tick its raised rate lasts through,
    REVEAL with its slot, REVEAL_ALL with the run its floor starts at,
    SET_DISTANCE with the distance and REMOVE with neither, 0 where none
--]]

function Wire.call(calls: Calls, kind: number, id: number, slot: number, value: number)
	local at: number = calls.count * CALL_BYTES
	local data: buffer = calls.data

	if at + CALL_BYTES > buffer.len(data) then
		local grown: buffer = buffer.create(buffer.len(data) * 2)
		buffer.copy(grown, 0, data, 0, at)
		calls.data = grown
		data = grown
	end

	buffer.writeu8(data, at, kind)
	buffer.writeu32(data, at + 1, id)
	buffer.writeu16(data, at + 5, slot)
	buffer.writef64(data, at + 7, value)
	calls.count += 1
end

--[[
    A worker's own hand-in: the calls queued for its views, then its first
    count hands in the front's order, each with no target followed by its
    rows of anti-ESP's answers, copied from visible and quiet at the hand's
    row. With resend, the worker sends every view it runs whole
--]]

function Wire.writeOwn(
	calls: Calls,
	hands: { Hand },
	count: number,
	visible: buffer,
	quiet: buffer,
	resend: boolean
): buffer
	bounded(count, "viewers")

	local callBytes: number = calls.count * CALL_BYTES
	local size: number = OWN_BYTES + callBytes + count * HAND_BYTES
	for index: number = 1, count do
		if hands[index].target == nil then
			size += ROW_BYTES * 2
		end
	end

	local data: buffer = buffer.create(size)
	buffer.writeu32(data, 0, calls.count)
	buffer.writeu16(data, 4, count)
	buffer.writeu8(data, 6, resend and RESEND or 0)
	buffer.copy(data, OWN_BYTES, calls.data, 0, callBytes)

	local at: number = OWN_BYTES + callBytes
	for index: number = 1, count do
		local hand: Hand = hands[index]
		local slot: number? = hand.slot
		local target: number? = hand.target
		local look: vector? = hand.look
		local position: vector = hand.position
		local flags: number = 0

		buffer.writeu32(data, at, hand.id)
		if slot ~= nil then
			flags += HAS_SLOT
			buffer.writeu16(data, at + 5, slot)
		end

		if target ~= nil then
			flags += HAS_TARGET
			buffer.writeu32(data, at + 7, target)
		end

		buffer.writef32(data, at + 11, position.x)
		buffer.writef32(data, at + 15, position.y)
		buffer.writef32(data, at + 19, position.z)
		if look ~= nil then
			flags += HAS_LOOK
			buffer.writef32(data, at + 23, look.x)
			buffer.writef32(data, at + 27, look.y)
			buffer.writef32(data, at + 31, look.z)
		end

		if hand.back then
			flags += BACK
		end

		if hand.zoomed then
			flags += ZOOMED
		end

		if hand.missed then
			flags += MISSED
		end

		buffer.writeu8(data, at + 4, flags)
		buffer.writeu16(data, at + 35, hand.acknowledged)
		buffer.writeu16(data, at + 37, hand.received)
		buffer.writeu16(data, at + 39, hand.sequence)
		buffer.writef64(data, at + 41, hand.traffic)
		buffer.writef64(data, at + 49, hand.team)
		at += HAND_BYTES

		if target == nil then
			buffer.copy(data, at, visible, hand.row, ROW_BYTES)
			buffer.copy(data, at + ROW_BYTES, quiet, hand.row, ROW_BYTES)
			at += ROW_BYTES * 2
		end
	end

	return data
end

-- How many calls an own hand-in carries
function Wire.callCount(data: buffer): number
	return buffer.readu32(data, 0)
end

-- Whether an own hand-in has its worker send every view it runs whole
function Wire.resend(data: buffer): boolean
	return bit32.btest(buffer.readu8(data, 6), RESEND)
end

-- An own hand-in's call at index from 1: its kind, id, slot and value
function Wire.readCall(data: buffer, index: number): (number, number, number, number)
	local at: number = OWN_BYTES + (index - 1) * CALL_BYTES

	return buffer.readu8(data, at),
		buffer.readu32(data, at + 1),
		buffer.readu16(data, at + 5),
		buffer.readf64(data, at + 7)
end

-- The hand at index of a list, made the first time the list holds that many
local function handAt(hands: { Hand }, index: number): Hand
	local kept: Hand? = hands[index]
	if kept then
		return kept
	end

	local made: Hand = {
		id = 0,
		slot = nil,
		target = nil,
		position = vector.zero,
		look = nil,
		acknowledged = 0,
		received = 0,
		sequence = 0,
		back = false,
		zoomed = false,
		missed = false,
		traffic = 0,
		team = 0,
		row = 0,
	}
	hands[index] = made

	return made
end

--[[
    Reads an own hand-in's viewers into hands, in order, each table made the
    first time the list holds that many and reused after, each visible row
    given as its offset in data, its quiet row behind it, and gives how many
--]]

function Wire.readOwn(data: buffer, hands: { Hand }): number
	local count: number = buffer.readu16(data, 4)
	local at: number = OWN_BYTES + buffer.readu32(data, 0) * CALL_BYTES

	for index: number = 1, count do
		local hand: Hand = handAt(hands, index)
		local flags: number = buffer.readu8(data, at + 4)
		hand.id = buffer.readu32(data, at)

		if bit32.btest(flags, HAS_SLOT) then
			hand.slot = buffer.readu16(data, at + 5)
		else
			hand.slot = nil
		end

		local target: number? = nil
		if bit32.btest(flags, HAS_TARGET) then
			target = buffer.readu32(data, at + 7)
		end

		hand.target = target
		hand.position =
			vector.create(buffer.readf32(data, at + 11), buffer.readf32(data, at + 15), buffer.readf32(data, at + 19))

		if bit32.btest(flags, HAS_LOOK) then
			hand.look = vector.create(
				buffer.readf32(data, at + 23),
				buffer.readf32(data, at + 27),
				buffer.readf32(data, at + 31)
			)
		else
			hand.look = nil
		end

		hand.back = bit32.btest(flags, BACK)
		hand.zoomed = bit32.btest(flags, ZOOMED)
		hand.missed = bit32.btest(flags, MISSED)
		hand.acknowledged = buffer.readu16(data, at + 35)
		hand.received = buffer.readu16(data, at + 37)
		hand.sequence = buffer.readu16(data, at + 39)
		hand.traffic = buffer.readf64(data, at + 41)
		hand.team = buffer.readf64(data, at + 49)
		at += HAND_BYTES

		hand.row = 0
		if target == nil then
			hand.row = at
			at += ROW_BYTES * 2
		end
	end

	return count
end

--[[
    A writer for a worker's results, its buffer kept and grown across runs
--]]

function Wire.writer(): Writer
	return {
		data = buffer.create(START_BYTES),
		at = 0,
		places = 0,
		rowBytes = 0,
		turns = 0,
		section = 0,
		asks = 0,
		marks = 0,
		events = 0,
		views = 0,
		viewsStart = 0,
		answers = buffer.create(CALLS_START),
		answerCount = 0,
	}
end

-- Makes room for bytes more in a writer's buffer, keeping what it holds
local function room(writer: Writer, bytes: number)
	local data: buffer = writer.data
	local needed: number = writer.at + bytes
	if needed <= buffer.len(data) then
		return
	end

	local grown: buffer = buffer.create(math.max(needed, buffer.len(data) * 2))
	buffer.copy(grown, 0, data, 0, writer.at)
	writer.data = grown
end

--[[
    Starts a writer's result for a run of a number of walk places, which
    each turn's rows of asks and marks hold a bit for
--]]

function Wire.begin(writer: Writer, places: number)
	writer.at = RESULT_BYTES
	writer.places = places
	writer.rowBytes = (places + BITS - 1) // BITS
	writer.turns = 0
	writer.views = 0
	writer.viewsStart = 0
	writer.answerCount = 0
end

--[[
    A watcher's answer from Turn.watch, kept in list order: nil when its
    target runs no turn on this worker, false when the target is overfull
--]]

function Wire.watch(writer: Writer, watched: boolean?)
	local count: number = writer.answerCount
	local answers: buffer = writer.answers
	if count == buffer.len(answers) then
		local grown: buffer = buffer.create(count * 2)
		buffer.copy(grown, 0, answers, 0, count)
		writer.answers = grown
		answers = grown
	end

	local answer: number = UNWATCHED
	if watched == true then
		answer = WATCHED
	elseif watched == false then
		answer = OVERFULL
	end

	buffer.writeu8(answers, count, answer)
	writer.answerCount = count + 1
end

--[[
    Starts a turn's section: the viewer's place from 1 in the worker's list
    and the ids of its recipients, the viewer then each watcher by bit, with
    empty rows of asks and marks and no events yet
--]]

function Wire.turn(writer: Writer, place: number, ids: { number }, count: number)
	local rowBytes: number = writer.rowBytes
	room(writer, SECTION_BYTES + count * ID_BYTES + rowBytes * 2 + 2)

	local data: buffer = writer.data
	local section: number = writer.at
	local at: number = section + SECTION_BYTES

	buffer.writeu16(data, section + 4, place)
	buffer.writeu8(data, section + 6, count)
	for index: number = 1, count do
		buffer.writeu32(data, at, ids[index])
		at += ID_BYTES
	end

	writer.asks = at
	writer.marks = at + rowBytes
	buffer.fill(data, at, 0, rowBytes * 2)
	at += rowBytes * 2

	writer.events = at
	buffer.writeu16(data, at, 0)
	at += 2

	buffer.writeu32(data, section, at - section)
	writer.section = section
	writer.at = at
	writer.turns += 1
end

-- Sets a walk place's bit from 1 in the row of the turn being written that starts at row
local function setPlace(writer: Writer, row: number, place: number)
	if not (place >= 1 and place <= writer.places) then
		error(`A relay worker asked anti-ESP about walk place {place}, outside this run's 1 to {writer.places}`)
	end

	local index: number = place - 1
	local data: buffer = writer.data
	local at: number = row + index // BITS

	buffer.writeu8(data, at, bit32.bor(buffer.readu8(data, at), bit32.lshift(1, index % BITS)))
end

--[[
    Marks the turn's ask of anti-ESP about the slot at a walk place from 1,
    which the front replays in viewer then walk order
--]]

function Wire.ask(writer: Writer, place: number)
	setPlace(writer, writer.asks, place)
end

--[[
    Marks the turn's ask about the slot at a walk place from 1 as one whose
    quiet bit was set, so it would only stamp its pair asked, which the
    front hands anti-ESP after the turn's asks in one call
--]]

function Wire.mark(writer: Writer, place: number)
	setPlace(writer, writer.marks, place)
end

-- Room for an event of bytes after its kind, its kind written, and where its body starts
local function event(writer: Writer, kind: number, bytes: number): number
	room(writer, 1 + bytes)

	local at: number = writer.at
	buffer.writeu8(writer.data, at, kind)

	return at + 1
end

-- Ends the event written up to at, counting it in its turn's section
local function counted(writer: Writer, at: number)
	local data: buffer = writer.data
	local count: number = buffer.readu16(data, writer.events) + 1
	bounded(count, "events a turn")

	buffer.writeu16(data, writer.events, count)
	buffer.writeu32(data, writer.section, at - writer.section)
	writer.at = at
end

-- Writes a block's bytes behind their u16 length at at, giving where they end
local function bytesAt(writer: Writer, at: number, block: buffer): number
	local length: number = buffer.len(block)
	buffer.writeu16(writer.data, at, length)
	buffer.copy(writer.data, at + 2, block, 0, length)

	return at + 2 + length
end

-- Writes a tap block's records as their slots behind their count at at, giving where they end
local function recordsAt(writer: Writer, at: number, block: Block.Block): number
	local data: buffer = writer.data
	local records: { number } = block.records
	local count: number = block.recordCount

	buffer.writeu16(data, at, count)
	at += 2
	for index: number = 1, count do
		buffer.writeu16(data, at, records[index] // RECORD_BYTES)
		at += 2
	end

	return at
end

-- The turn's next block, as its send port was handed it
function Wire.send(writer: Writer, block: buffer)
	counted(writer, bytesAt(writer, event(writer, SEND, 2 + buffer.len(block)), block))
end

--[[
    The turn's next tap on a block, its records and, when bytes is given,
    the bytes it was handed; with none, the block just sent's
--]]

function Wire.relayed(writer: Writer, block: Block.Block, bytes: buffer?)
	local records: number = 2 + block.recordCount * 2

	if bytes then
		local at: number = event(writer, RELAYED_BYTES, 2 + buffer.len(bytes) + records)
		counted(writer, recordsAt(writer, bytesAt(writer, at, bytes), block))
	else
		counted(writer, recordsAt(writer, event(writer, RELAYED, records), block))
	end
end

-- The sequence the turn's last block recorded for its recipients
function Wire.heard(writer: Writer, sequence: number)
	local at: number = event(writer, HEARD, 2)
	buffer.writeu16(writer.data, at, sequence)
	counted(writer, at + 2)
end

-- The turn's next withheld block, to its watchers alone
function Wire.withheld(writer: Writer, block: buffer)
	counted(writer, bytesAt(writer, event(writer, WITHHELD_SEND, 2 + buffer.len(block)), block))
end

-- The turn's tap on the withheld block just sent, by its records
function Wire.withheldTap(writer: Writer, block: Block.Block)
	counted(writer, recordsAt(writer, event(writer, WITHHELD_TAP, 2 + block.recordCount * 2), block))
end

-- A view's facts for a slot as its copy keeps them, each 0 where the mark it belongs to is clear
local function facts(view: View, slot: number): (number, number, number, number)
	local flags: number = buffer.readu16(view.flags, slot * 2)
	local marks: number, life: number, kind: number, held: number = 0, 0, 0, 0

	if bit32.btest(flags, SENT) then
		marks = FACT_SENT
		life = buffer.readu8(view.generations, slot)
		kind = buffer.readu8(view.kinds, slot)
	end

	if bit32.btest(flags, OWN) then
		marks += FACT_OWN
		life = buffer.readu8(view.generations, slot)
	end

	local withheld: Turn.Withheld? = view.withheld
	if withheld and bit32.btest(buffer.readu8(withheld.flags, slot), WITHHELD) then
		marks += FACT_WITHHELD
		held = buffer.readu8(withheld.lives, slot)
	end

	return marks, life, kind, held
end

-- A copy's facts for a slot, laid out as facts gives a view's
local function copyFacts(copy: Copy, slot: number): (number, number, number, number)
	local flags: number = buffer.readu16(copy.flags, slot * 2)
	local marks: number, held: number = 0, 0

	if bit32.btest(flags, SENT) then
		marks = FACT_SENT
	end

	if bit32.btest(flags, OWN) then
		marks += FACT_OWN
	end

	local withheld: Withheld? = copy.withheld
	if withheld and bit32.btest(buffer.readu8(withheld.flags, slot), WITHHELD) then
		marks += FACT_WITHHELD
		held = buffer.readu8(withheld.lives, slot)
	end

	return marks, buffer.readu8(copy.generations, slot), buffer.readu8(copy.kinds, slot), held
end

-- A copy's withheld set, empty
local function heldCopy(): Withheld
	return { flags = buffer.create(SLOTS), lives = buffer.create(SLOTS) }
end

-- Sets a copy's facts for a slot
local function keep(copy: Copy, slot: number, marks: number, life: number, kind: number, held: number)
	local flags: number = 0
	if bit32.btest(marks, FACT_SENT) then
		flags = SENT
	end

	if bit32.btest(marks, FACT_OWN) then
		flags += OWN
	end

	buffer.writeu16(copy.flags, slot * 2, flags)
	buffer.writeu8(copy.generations, slot, life)
	buffer.writeu8(copy.kinds, slot, kind)

	local withheld: Withheld? = copy.withheld
	if not withheld then
		if bit32.btest(marks, FACT_WITHHELD) then
			error(`A view's copy was given a withheld slot {slot} before its withheld set`)
		end

		return
	end

	local mark: number = 0
	if bit32.btest(marks, FACT_WITHHELD) then
		mark = WITHHELD
	end

	buffer.writeu8(withheld.flags, slot, mark)
	buffer.writeu8(withheld.lives, slot, held)
end

--[[
    An empty copy of a view, which the front keeps for each view a worker
    hosts and a worker keeps as its shadow of what the front holds
--]]

function Wire.copy(): Copy
	return {
		own = nil,
		tracked = {},
		flags = buffer.create(SLOTS * 2),
		generations = buffer.create(SLOTS),
		kinds = buffer.create(SLOTS),
		withheld = nil,
	}
end

--[[
    The changes to the copy of a view, keyed by its id, since shadow, the
    worker's own copy, was brought level with it: its own slot, whether it
    has a withheld set, the facts of each slot it tracked then or tracks
    now that differ, and each place of its tracked list that changed, with
    the list's length. Shadow is brought level as they are written
--]]

function Wire.view(writer: Writer, id: number, view: View, shadow: Copy)
	local old: { number } = shadow.tracked
	local new: { number } = view.tracked
	local oldCount: number = #old
	local newCount: number = #new
	room(writer, VIEW_BYTES + (oldCount + newCount) * FACT_BYTES + 4 + newCount * CHANGE_BYTES)

	if writer.views == 0 then
		writer.viewsStart = writer.at
	end

	local data: buffer = writer.data
	local start: number = writer.at
	local own: number? = view.own

	buffer.writeu32(data, start, id)
	if own == nil then
		buffer.writeu16(data, start + 4, NO_SLOT)
	else
		buffer.writeu16(data, start + 4, own)
	end

	if view.withheld then
		buffer.writeu8(data, start + 6, 1)
		if not shadow.withheld then
			shadow.withheld = heldCopy()
		end
	else
		buffer.writeu8(data, start + 6, 0)
	end

	-- Every slot tracked before or now, so a slot let go has its facts cleared
	local at: number = start + VIEW_BYTES
	local count: number = 0
	for index: number = 1, oldCount + newCount do
		local slot: number
		if index <= oldCount then
			slot = old[index]
		else
			slot = new[index - oldCount]
		end

		local marks: number, life: number, kind: number, held: number = facts(view, slot)
		local keptMarks: number, keptLife: number, keptKind: number, keptHeld: number = copyFacts(shadow, slot)
		if marks ~= keptMarks or life ~= keptLife or kind ~= keptKind or held ~= keptHeld then
			buffer.writeu16(data, at, slot)
			buffer.writeu8(data, at + 2, marks)
			buffer.writeu8(data, at + 3, life)
			buffer.writeu8(data, at + 4, kind)
			buffer.writeu8(data, at + 5, held)
			keep(shadow, slot, marks, life, kind, held)
			count += 1
			at += FACT_BYTES
		end
	end

	buffer.writeu16(data, start + 7, count)

	local changesAt: number = at + 2
	local changes: number = 0
	buffer.writeu16(data, at, newCount)
	at += 4

	for index: number = 1, newCount do
		local slot: number = new[index]
		if old[index] ~= slot then
			buffer.writeu16(data, at, index)
			buffer.writeu16(data, at + 2, slot)
			old[index] = slot
			changes += 1
			at += CHANGE_BYTES
		end
	end

	for index: number = newCount + 1, oldCount do
		old[index] = nil
	end

	buffer.writeu16(data, changesAt, changes)
	shadow.own = own
	writer.at = at
	writer.views += 1
end

--[[
    Ends a writer's result and gives it in a buffer of its exact length:
    the run's counts, the place from 1 of the viewer whose turn threw, 0 for
    none, with its error's text, and each watcher's answer
--]]

function Wire.finish(
	writer: Writer,
	sent: number,
	cut: number,
	visited: number,
	rest: number,
	failed: number,
	failure: string
): buffer
	local length: number = math.min(#failure, U16_TOP)
	local answerCount: number = writer.answerCount
	room(writer, answerCount + length)

	bounded(math.max(writer.turns, writer.views, answerCount), "turns, views or answers")

	local data: buffer = writer.data
	local at: number = writer.at
	local viewsStart: number = at
	if writer.views > 0 then
		viewsStart = writer.viewsStart
	end

	local answersStart: number = at
	buffer.copy(data, at, writer.answers, 0, answerCount)
	at += answerCount

	local failureStart: number = at
	buffer.writestring(data, at, failure, length)
	at += length

	buffer.writeu16(data, 0, writer.turns)
	buffer.writeu16(data, 2, writer.views)
	buffer.writeu16(data, 4, answerCount)
	buffer.writeu16(data, 6, writer.places)
	buffer.writeu32(data, 8, sent)
	buffer.writeu32(data, 12, cut)
	buffer.writeu32(data, 16, visited)
	buffer.writeu16(data, 20, failed)
	buffer.writeu16(data, 22, length)
	buffer.writeu32(data, 24, viewsStart)
	buffer.writeu32(data, 28, answersStart)
	buffer.writeu32(data, 32, failureStart)
	buffer.writeu32(data, 36, rest)

	local result: buffer = buffer.create(at)
	buffer.copy(result, 0, data, 0, at)

	return result
end

--[[
    A reader of workers' results, whose taps' records point into records,
    the front's own record of each slot, which holds this run's records as
    every worker's does
--]]

function Wire.reader(records: buffer): Reader
	local tap: Block.Block = Block.new()
	tap.recordData = records

	return {
		data = buffer.create(0),
		turns = 0,
		views = 0,
		answers = 0,
		places = 0,
		sent = 0,
		cut = 0,
		visited = 0,
		rest = 0,
		failed = 0,
		failure = "",
		place = 0,
		recipients = {},
		recipientCount = 0,
		block = buffer.create(0),
		sequence = 0,
		tap = tap,
		_at = 0,
		_turn = 0,
		_asks = 0,
		_marks = 0,
		_event = 0,
		_left = 0,
		_view = 0,
		_viewAt = 0,
		_viewEnd = 0,
		_answersAt = 0,
	}
end

--[[
    Opens one worker's result: its counts and failure, with its first turn
    and view next to read
--]]

function Wire.open(reader: Reader, data: buffer)
	reader.data = data
	reader.turns = buffer.readu16(data, 0)
	reader.views = buffer.readu16(data, 2)
	reader.answers = buffer.readu16(data, 4)
	reader.places = buffer.readu16(data, 6)
	reader.sent = buffer.readu32(data, 8)
	reader.cut = buffer.readu32(data, 12)
	reader.visited = buffer.readu32(data, 16)
	reader.rest = buffer.readu32(data, 36)
	reader.failed = buffer.readu16(data, 20)
	reader.failure = buffer.readstring(data, buffer.readu32(data, 32), buffer.readu16(data, 22))
	reader._at = RESULT_BYTES
	reader._turn = 0
	reader._left = 0
	reader._view = 0
	reader._viewEnd = buffer.readu32(data, 24)
	reader._answersAt = buffer.readu32(data, 28)
end

-- The answer Turn.watch gave the worker's watcher at index from 1, in its list's order
function Wire.watched(reader: Reader, index: number): boolean?
	local answer: number = buffer.readu8(reader.data, reader._answersAt + index - 1)
	if answer == WATCHED then
		return true
	elseif answer == OVERFULL then
		return false
	end

	return nil
end

--[[
    Moves to the result's next turn, false past the last: its viewer's
    place and its recipients' ids, with its asks, marks and events next to
    read
--]]

function Wire.nextTurn(reader: Reader): boolean
	if reader._turn == reader.turns then
		return false
	end

	local data: buffer = reader.data
	local section: number = reader._at
	local count: number = buffer.readu8(data, section + 6)
	local recipients: { number } = reader.recipients
	local at: number = section + SECTION_BYTES

	reader.place = buffer.readu16(data, section + 4)
	for index: number = 1, count do
		recipients[index] = buffer.readu32(data, at)
		at += ID_BYTES
	end

	for index: number = count + 1, #recipients do
		recipients[index] = nil
	end

	local rowBytes: number = (reader.places + BITS - 1) // BITS
	reader.recipientCount = count
	reader._asks = at
	reader._marks = at + rowBytes
	at += rowBytes * 2

	reader._left = buffer.readu16(data, at)
	reader._event = at + 2
	reader._at = section + buffer.readu32(data, section)
	reader._turn += 1

	return true
end

-- Fills places with each walk place from 1 whose bit is set in the turn's row that starts at row, and gives how many
local function placesIn(reader: Reader, row: number, places: { number }): number
	local data: buffer = reader.data
	local count: number = 0

	for index: number = 0, (reader.places + BITS - 1) // BITS - 1 do
		local byte: number = buffer.readu8(data, row + index)

		-- Each set bit, lowest first, cleared as it is read
		while byte ~= 0 do
			count += 1
			places[count] = index * BITS + bit32.countrz(byte) + 1
			byte = bit32.band(byte, byte - 1)
		end
	end

	return count
end

--[[
    Fills places with each walk place from 1 at which the turn asked
    anti-ESP, in walk order, the order the front replays them in, and gives
    how many; places past that count are left as they were
--]]

function Wire.asks(reader: Reader, places: { number }): number
	return placesIn(reader, reader._asks, places)
end

--[[
    Fills places with each walk place from 1 the turn marked, in walk order,
    the order the front hands their slots to anti-ESP in after the turn's
    asks, and gives how many; places past that count are left as they were
--]]

function Wire.marks(reader: Reader, places: { number }): number
	return placesIn(reader, reader._marks, places)
end

-- A buffer of exactly length bytes for the front to hand a block on in, made the first time that length is read
local function exact(length: number): buffer
	local kept: buffer? = Outgoing[length]
	if kept then
		return kept
	end

	local made: buffer = buffer.create(length)
	Outgoing[length] = made

	return made
end

-- Reads the bytes behind a u16 length at at into the reader's block, giving where they end
local function blockAt(reader: Reader, at: number): number
	local length: number = buffer.readu16(reader.data, at)
	local block: buffer = exact(length)
	buffer.copy(block, 0, reader.data, at + 2, length)
	reader.block = block

	return at + 2 + length
end

-- Reads a tap's records at at into the reader's tap block, giving where they end
local function tapAt(reader: Reader, at: number): number
	local data: buffer = reader.data
	local tap: Block.Block = reader.tap
	local records: { number } = tap.records
	local count: number = buffer.readu16(data, at)

	at += 2
	for index: number = 1, count do
		records[index] = buffer.readu16(data, at) * RECORD_BYTES
		at += 2
	end

	tap.recordCount = count

	return at
end

--[[
    Reads the turn's next event and gives its kind, 0 past the last: SEND
    and WITHHELD with the bytes in block; RELAYED and WITHHELD_TAP with the
    tap's records in tap and its bytes in block; HEARD with its sequence
--]]

function Wire.nextEvent(reader: Reader): number
	if reader._left == 0 then
		return 0
	end

	local at: number = reader._event
	local kind: number = buffer.readu8(reader.data, at)
	at += 1

	if kind == SEND or kind == WITHHELD_SEND then
		at = blockAt(reader, at)
	elseif kind == RELAYED or kind == WITHHELD_TAP then
		at = tapAt(reader, at)
	elseif kind == RELAYED_BYTES then
		at = tapAt(reader, blockAt(reader, at))
		kind = RELAYED
	elseif kind == HEARD then
		reader.sequence = buffer.readu16(reader.data, at)
		at += 2
	else
		error(`A relay worker's result holds an event of kind 1 to 6, not {kind}`)
	end

	reader._event = at
	reader._left -= 1

	return kind
end

--[[
    Moves to the result's next view and gives its id, 0 past the last, its
    changes next for applyView to read
--]]

function Wire.nextView(reader: Reader): number
	if reader._view == reader.views then
		return 0
	end

	local data: buffer = reader.data
	local at: number = reader._viewEnd
	local tracked: number = at + VIEW_BYTES + buffer.readu16(data, at + 7) * FACT_BYTES

	reader._viewAt = at
	reader._viewEnd = tracked + 4 + buffer.readu16(data, tracked + 2) * CHANGE_BYTES
	reader._view += 1

	return buffer.readu32(data, at)
end

--[[
    Brings a copy of the view nextView last moved to level with the view
    as its worker left it this run
--]]

function Wire.applyView(reader: Reader, copy: Copy)
	local data: buffer = reader.data
	local at: number = reader._viewAt
	local own: number = buffer.readu16(data, at + 4)

	if own == NO_SLOT then
		copy.own = nil
	else
		copy.own = own
	end

	if buffer.readu8(data, at + 6) ~= 0 and not copy.withheld then
		copy.withheld = heldCopy()
	end

	local count: number = buffer.readu16(data, at + 7)
	at += VIEW_BYTES
	for _ = 1, count do
		keep(
			copy,
			buffer.readu16(data, at),
			buffer.readu8(data, at + 2),
			buffer.readu8(data, at + 3),
			buffer.readu8(data, at + 4),
			buffer.readu8(data, at + 5)
		)
		at += FACT_BYTES
	end

	local tracked: { number } = copy.tracked
	local length: number = buffer.readu16(data, at)
	local changes: number = buffer.readu16(data, at + 2)
	at += 4
	for _ = 1, changes do
		tracked[buffer.readu16(data, at)] = buffer.readu16(data, at + 2)
		at += CHANGE_BYTES
	end

	for index: number = length + 1, #tracked do
		tracked[index] = nil
	end
end

return Wire
