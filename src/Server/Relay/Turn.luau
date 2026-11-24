--[[
    The relay's per-viewer core: every view and what a viewer's turn does to
    it, reading only the world of per-slot facts the front fills each run and
    calling out only through the ports start hands it
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Parent.Codec.Block)
local Change = require(script.Parent.Parent.Parent.Codec.Change)
local Constants = require(script.Parent.Parent.Parent.Constants)
local Math = require(script.Parent.Parent.Parent.Step.Math)
local Sequence = require(script.Parent.Parent.Parent.Codec.Sequence)

local SLOTS: number = Constants.SLOTS
local RECORD_BYTES: number = Constants.RECORD_BYTES
local BLOCK_BYTES: number = Constants.MAX_RELAY_BYTES
local HEADER_BYTES: number = Constants.RELAY_HEADER_BYTES
local REVEAL_BYTES: number = Constants.REVEAL_BYTES
local HIDE_BYTES: number = Constants.HIDE_BYTES
local FOOTSTEP_BYTES: number = Constants.FOOTSTEP_BYTES
local MAX_LOOK: number = Constants.MAX_LOOK
local MAX_HELD: number = Constants.MAX_HELD
local DEPTH: number = Constants.CHANGE_DEPTH -- Relay runs of records the history keeps, so a baseline is 1 to 31 back
local WRAP: number = 2 ^ 16 -- The values a u16 wire number wraps through
local SEQUENCES: number = WRAP - Constants.FIRST_SEQUENCE -- A viewer's sequences run 1 to 65,535, so 0 still means none
local SECTION_LIMIT: number = 2 ^ 8 - 1 -- The most entries a block's u8 counts hold
local FRAME_BYTES: number = 3 -- Volt's event id and the buffer's u16 length in front of each block it sends

-- A target's record goes on each of this many band ticks after it stops changing, then once every STILL_SECONDS
-- while it stays still, so a lost last update freezes a pose for at most that long
local REST_REPEATS: number = 3
local STILL_SECONDS: number = 1

-- The most band ticks a pair's credit holds once a turn that follows a missed one adds every relay tick since: one
-- owed, as a record cut keeps, and this run's, the most any other turn leaves it with
local MOST_CREDIT: number = 2

-- What a viewer's acknowledgment can clear: the blocks it can still name and the pending entries and records they
-- carried, each logged as its slot times ENTRY_PARTS plus its part
local RING: number = 64
local LOG: number = 8192
local ENTRY_PARTS: number = 6
local VISIBILITY: number = 0 -- A reveal or a hide
local LOOK_PART: number = 1
local HELD_PART: number = 2
local WITHHELD_LOOK_PART: number = 3 -- A withheld character's look, which rides the withheld block beside the copy
local WITHHELD_HELD_PART: number = 4
local RECORD_PART: number = 5 -- A record, logged while records go as changes, a baseline once acknowledged

-- Each block keeps the recipients still to acknowledge it as a mask, a bit each: SELF its own viewer, and each
-- moderator watching that viewer the bit it was given, 1 to MAX_WATCHERS
-- Whiteoak TODO: the mask is a u32, so one target takes at most 31 watchers; more needs a wider mask per block, two
-- u32s or a buffer of bits a block, once a game puts more than 31 moderators on one target
local SELF: number = 2 ^ 0
local MAX_WATCHERS: number = Constants.MAX_WATCHERS

local STEP_START: number = 256 -- The steps one run holds before the front grows their buffers

-- Each part of a turn the relay's clocks time, its place from 0 in the order Wire.CLOCKS names them first
local LAP: { [string]: number } = { head = 0, gather = 1, measure = 2, settle = 3, schedule = 4, place = 5, send = 6 }
local LAPS: number = 7 -- The parts LAP numbers

-- What a viewer holds for a slot, a bit each but the last three, which count the band edges the slot is inside, from
-- the outermost in, so 0 is the farthest band; an NPC's one edge is npcs.near. Bit 1 is free
local RELEVANT: number = 2 ^ 0 -- Inside its relevancy for the slot's kind
local CULLED: number = 2 ^ 2 -- Relevant and hidden by anti-ESP this run, so its steps may be heard
local SENT: number = 2 ^ 3 -- Currently sent: from the tick its reveal is first carried until its hide is
local REVEAL: number = 2 ^ 4 -- A reveal pending
local HIDE: number = 2 ^ 5 -- A hide pending
local VISIBILITY_CARRIED: number = 2 ^ 6 -- The pending reveal or hide has ridden a block since it last changed
local LOOK: number = 2 ^ 7 -- The look pending
local LOOK_CARRIED: number = 2 ^ 8
local HELD: number = 2 ^ 9 -- The held item pending
local HELD_CARRIED: number = 2 ^ 10
local OWN: number = 2 ^ 11 -- The viewer's own character, whose looks it is given and which it is never sent
local OUTSIDE: number = 2 ^ 12 -- Held to the out-of-view rate on its last run, so it is owed a record once it isn't
local EDGES_AT: number = 13 -- The first of the edge count's bits
local EDGES_WIDTH: number = 3 -- Its bits, which count up to Constants.MAX_BANDS less 1 edges
local EDGES: number = (2 ^ EDGES_WIDTH - 1) * 2 ^ EDGES_AT -- All of them, cleared whenever relevancy is
local LOOKS: number = LOOK + LOOK_CARRIED + HELD + HELD_CARRIED
local STRETCH: number = SENT + REVEAL + HIDE + VISIBILITY_CARRIED + LOOKS -- All a stretch of being sent holds
local KEEP: number = RELEVANT + SENT + REVEAL + HIDE + LOOK + HELD + OWN -- Any of these keeps a slot tracked

-- What a watched target's withheld block holds for a slot, a bit each
local WITHHELD: number = 2 ^ 0 -- A culled player the target is not sent, which its watchers get
local WITHHELD_LOOK: number = 2 ^ 1 -- Its look pending for the watchers
local WITHHELD_LOOK_CARRIED: number = 2 ^ 2
local WITHHELD_HELD: number = 2 ^ 3 -- Its held item pending for them
local WITHHELD_HELD_CARRIED: number = 2 ^ 4

-- Each kind's code, its place in Block's list from 0, which a reveal and a keyframe carry
local KIND_CODES: { [string]: number } = {}
for index: number, kind: Block.Kind in Block.KINDS do
	KIND_CODES[kind] = index - 1
end

local PLAYER: number = KIND_CODES.Player
local NPC: number = KIND_CODES.Npc
local SLEEPER: number = KIND_CODES.Sleeper

type Bot = { Name: string }
type Key = Player | Bot

-- One viewer as the front hands it to a turn, the server handle's own table
export type Viewer = {
	key: Key, -- The player or bot, a handle a turn keeps its view under and hands the ports, never reading it
	slot: number?, -- Its own character's slot, nil while it has none
	position: vector, -- Where its relevancy, bands and earshot are measured from
	acknowledged: number, -- The newest relay sequence its client received, 0 for none
	received: number, -- The mask of the 16 sequences before that one, bit 0 the one just before
	target: Key?, -- The viewer it spectates, whose blocks it gets copies of in place of its own; nil for none
	look: vector?, -- The newest look its client sent, a unit vector on the ground; nil before any
	zoomed: boolean?, -- Whether its players go at the nearest band's rates wherever they stand; nil as false
}

-- The out-of-view rate as a turn reads it: the rate, the radius squared, and the cone's half-angle as its cosine
-- squared, with whether it is wider than a quarter turn
export type OutOfView = {
	rate: number,
	radiusSquared: number,
	cosineSquared: number,
	wide: boolean,
}

-- The game's settings as a turn reads them, worked out by the front once at start: the radii each viewer's own
-- render distance caps in studs, the rest of each distance squared, each rate in hertz and each budget in bytes a
-- second. The bands come with each run, in a Tuning
export type Settings = {
	relayRate: number,
	enter: number, -- relevancy.enter
	leave: number, -- relevancy.leave
	sleepers: number, -- sleepers.radius
	npcs: number, -- npcs.range
	weightNear: number,
	weightFar: number,
	weightShooter: number,
	weightCone: number,
	shotRate: number,
	soft: number,
	hard: number,
	npcNearSquared: number,
	npcFarRate: number,
	earshot: { number }, -- Each footstep kind's squared range by its code, negative for a kind the game gives none
	outOfView: OutOfView?, -- Nil while the game gives none, so no player is held to it
	changes: boolean, -- Whether records go as changes
	clocks: boolean, -- Whether each turn times its parts, as relay.clocks says
}

-- The distance bands as a run's turns read them, which the front works out from tiers.bands and tiers.edges and hands
-- in each run: the band count, the crowd cap's flags, size, rate and floor, all 0 while there is none, each band's aim
-- and floor in hertz, nearest first, and each edge's enter and leave in studs squared, the nearest first
export type Tuning = {
	bands: number,
	flags: number,
	crowdSize: number,
	crowdRate: number,
	crowdFloor: number,
	aims: { number },
	floors: { number },
	enters: { number },
	leaves: { number },
}

-- Everything a turn calls outside itself, handed in once at start
export type Ports = {
	send: (keys: { Key }, data: buffer) -> (), -- One block to a viewer and the moderators watching it
	sendWithheld: (keys: { Key }, data: buffer) -> (), -- One withheld block to those moderators
	heard: (keys: { Key }, count: number, sequence: number) -> (), -- The first count keys were sent that block
	traffic: (key: Key) -> number, -- Volt's count of the bytes sent to a viewer over the last second
	isHidden: (viewer: Viewer, slot: number) -> boolean, -- Anti-ESP's answer for a pair
	valid: (slot: number) -> boolean, -- Whether a value is one of the slot table's slots
	observing: () -> boolean, -- Whether a sink observes any viewer's blocks or withheld records
	observes: (keys: { Key }, count: number) -> boolean, -- Whether a sink observes any of the first count keys
	relayed: (keys: { Key }, count: number, block: Block.Block, data: buffer) -> (), -- The taps' copy of a block
	withheld: (target: Key, block: Block.Block, data: buffer) -> (), -- And of a withheld block
}

-- This run's footsteps: whose each is, its kind, where it fell, and its entry, encoded once for every viewer. Past the
-- count, carried more of the run before's, kept for a turn that follows a run its viewer was left
export type Steps = {
	count: number,
	carried: number,
	capacity: number, -- The steps the buffers hold before they grow
	slots: buffer, -- u16
	kinds: buffer, -- u8: its kind's code from 1
	places: { vector }, -- By step from 1
	data: buffer, -- Its entry
}

-- Each slot's facts as every turn reads them, which the front fills each run, by slot in buffers, and the looks and
-- held items the front sets between runs
export type World = {
	present: buffer, -- u32: the last run it was handed in with an entry
	generations: buffer, -- u8: its life
	kinds: buffer, -- u8: its kind's code
	unparked: buffer, -- u32: the last run it was in the states and not Parked
	facings: buffer, -- f64: its body's facing this run
	positions: { vector }, -- By slot plus 1: where it stood this run
	walk: buffer, -- u16 by place from 1: the slot at it in this run's walk of the states
	records: buffer, -- Its record encoded this run
	changed: buffer, -- u32: the relay tick its record last changed, unwrapped
	history: buffer, -- Every slot's record over the last DEPTH runs while records go as changes, a plane a run
	looks: buffer, -- Its look, packed
	lookLengths: buffer, -- u8
	lookVersions: buffer, -- u16: moving on with each change
	lookLives: buffer, -- u8: the generation plus 1 its look was set for, 0 for none
	helds: buffer, -- Its held item, packed
	heldLengths: buffer, -- u8: 0 while nothing is held
	heldVersions: buffer, -- u16
	invisible: buffer, -- u8: the generation plus 1 it is invisible for, 0 for none
	steps: Steps,
}

-- One kind's bodies this run: a list of slots for each square cell of the play area, row by row, each in the order the
-- states were walked, and the cells the turn whose view it is reaches
type Cells = {
	radius: number, -- The farthest the kind is relevant, which a view's distance caps
	size: number, -- A cell's side in studs
	across: number, -- The cells along each side
	heads: buffer, -- u16 by cell: its list's first slot plus 1, 0 for none
	tails: buffer, -- u16 by cell: its list's last slot
	westmost: number, -- The lowest column holding a body this run, across while none does
	eastmost: number, -- The highest, -1 while none does
	southmost: number, -- And the same for the rows
	northmost: number,
	west: number, -- The lowest column the turn reaches, held to the kind's own, so a kind with no body reaches none
	east: number,
	south: number, -- And the same for the rows
	north: number,
}

-- Where this run's bodies stand: each kind's in cells of its own, so a viewer's turn visits the cells each kind's reach
-- spans in place of every body
type Grid = {
	cells: { Cells }, -- Each kind's, by its code plus 1, made at start
	following: buffer, -- u16 by slot: the next slot in its cell's list plus 1, 0 at the end
	columns: buffer, -- u16 by slot: its cell's column this run, in its kind's cells
	rows: buffer, -- u16 by slot: and its row
	orders: buffer, -- u16 by slot: its place from 1 in this run's walk of the states
	walk: buffer, -- u16 by place: the slot at it
	positions: { vector }, -- By slot plus 1: where it stood this run
	count: number, -- The bodies this run filed
	visits: { number }, -- A turn's slots to visit, each as its place times SLOTS plus the slot
	visited: number, -- The bodies the turns have gathered since start
}

-- What a watched target's withheld block keeps for each slot, by slot in buffers
export type Withheld = {
	flags: buffer, -- u8
	lives: buffer, -- u8: the generation its withheld stretch belongs to
	lookSent: buffer, -- u16: the look version the watchers were last given
	heldSent: buffer,
	lookFrom: buffer, -- u16: the copy the pending look first rode beside since it last changed
	heldFrom: buffer,
	aim: buffer, -- f32: the band ticks it is owed at its band's aim rate
}

-- What the relay keeps for one viewer: the slots it holds anything for, each field a buffer by slot, the blocks
-- its acknowledgment can still name with the pending entries each carried, and the moderators watching it
export type View = {
	key: Key,
	distance: number, -- Its client's render distance held to relevancy.leave, which is what it has until one comes
	sequence: number, -- The message sequence its next block takes
	newest: number, -- The sequence of the last block it was sent, 0 before the first
	turn: number, -- The last run it was handed in with no target, so its own view ran
	turned: number, -- The relay tick, unwrapped, its own last turn ran on, 0 before the first
	own: number?, -- Its own character's slot when it last ran
	tracked: { number },
	places: buffer, -- u16: each tracked slot's place in tracked, 0 for none
	flags: buffer, -- u16
	generations: buffer, -- u8: the life its stretch, or its own look, belongs to
	kinds: buffer, -- u8: the kind code its reveal carries
	visibilityFrom: buffer, -- u16: the first block the pending reveal or hide rode since it last changed
	lookFrom: buffer, -- u16: the same for each part of a look
	heldFrom: buffer,
	lookSent: buffer, -- u16: the look version it was last given
	heldSent: buffer,
	repeats: buffer, -- u8: the rest repeats left
	lastRecord: buffer, -- u32: the relay tick its last record went in, unwrapped, 0 for none
	shotUntil: buffer, -- u32: the last relay tick a shot near it raises that shooter's rate
	aim: buffer, -- f32: the band ticks it is owed at the target's aim rate
	floor: buffer, -- f32: and at its floor rate
	baseRuns: buffer, -- u32: the newest run whose record every recipient acknowledged, 0 for none; empty unless changes
	baseFloor: number, -- The first run whose blocks may give a baseline, so one acknowledged before it is never used
	ringSequences: buffer, -- u32: each remembered block's sequence plus 1, 0 for none
	ringRuns: buffer, -- u32: the run it went in
	ringStarts: buffer, -- f64: where its entries start in the log
	ringCounts: buffer, -- u16: how many it carried
	ringOwed: buffer, -- u32: the mask of its recipients still to acknowledge it
	log: buffer, -- u16 a pending entry
	logHead: number, -- The entries ever logged
	watchers: { [number]: Key }, -- The moderators watching it, by their bit
	bits: { [Key]: number },
	watcherRuns: buffer, -- u32: the last run each bit's watcher was handed in watching it
	watcherCount: number,
	withheld: Withheld?, -- Its withheld block's state, made the first time it is watched
}

-- What start hands in, each set before the front lets any turn run
local Send: (keys: { Key }, data: buffer) -> ()
local SendWithheld: (keys: { Key }, data: buffer) -> ()
local Heard: (keys: { Key }, count: number, sequence: number) -> ()
local Traffic: (key: Key) -> number
local IsHidden: (viewer: Viewer, slot: number) -> boolean
local Valid: (slot: number) -> boolean
local Observing: () -> boolean
local Observes: (keys: { Key }, count: number) -> boolean
local Relayed: (keys: { Key }, count: number, block: Block.Block, data: buffer) -> ()
local TapWithheld: (target: Key, block: Block.Block, data: buffer) -> ()

-- The game's settings as a turn reads them, but the radii each viewer's own render distance caps, in studs, and the
-- grid that finds the bodies inside them, which share one table since Luau caps a chunk's locals
local RelayRate: number = 0
local StillTicks: number = 0
local Radii: { enter: number, leave: number, sleepers: number, npcs: number, grid: Grid } = {
	enter = 0,
	leave = 0,
	sleepers = 0,
	npcs = 0,
	grid = {
		cells = {},
		following = buffer.create(SLOTS * 2),
		columns = buffer.create(SLOTS * 2),
		rows = buffer.create(SLOTS * 2),
		orders = buffer.create(SLOTS * 2),
		walk = buffer.create((SLOTS + 1) * 2),
		positions = table.create(SLOTS, vector.zero),
		count = 0,
		visits = {},
		visited = 0,
	},
}
local Tune: Tuning -- This run's bands, set by each begin
local WeightNear: number = 0
local WeightFar: number = 0
local WeightShooter: number = 0
local WeightCone: number = 0
local ShotRate: number = 0
local Soft: number = 0
local Hard: number = 0
local NpcNearSquared: number = 0
local NpcFarRate: number = 0
local Earshot: { number } = {} -- Each footstep kind's squared range
local OutOfViewRate: OutOfView? = nil -- Nil while the game gives none, so no player is held to it

-- The radii of the viewer whose turn it is, squared, from its render distance, found once a turn
local EnterSquared: number = 0
local LeaveSquared: number = 0
local SleeperSquared: number = 0
local NpcRangeSquared: number = 0

local Run: number = 0 -- The relay runs so far, which every timing but those in seconds counts in
local RunTick: number = 0 -- The relay tick of this run, or the last, unwrapped, which the timings in seconds count in
local Elapsed: number = 1 -- The relay ticks since the run before, more than 1 after runs a catch-up skipped
local TickWire: number = 0 -- The relay tick this run's blocks carry, a u16
local RecordsSent: number = 0 -- The records the band ticks' lists placed in a block, since start
local RecordsCut: number = 0 -- And those a viewer's room left out

-- With relay.clocks on, the seconds each part of this run's turns took, summed over the turns, an f64 a part by its
-- place in LAP, and when the part being timed began
local Clock: { on: boolean, laps: buffer, from: number } = { on = false, laps = buffer.create(LAPS * 8), from = 0 }

-- The world's buffers, each also held here so a turn reads it as an upvalue
local Present: buffer = buffer.create(SLOTS * 4)
local Generations: buffer = buffer.create(SLOTS)
local Kinds: buffer = buffer.create(SLOTS)
local Unparked: buffer = buffer.create(SLOTS * 4)
local Facings: buffer = buffer.create(SLOTS * 8)
local Records: buffer = buffer.create(SLOTS * RECORD_BYTES)
local Changed: buffer = buffer.create(SLOTS * 4)
local Looks: buffer = buffer.create(SLOTS * MAX_LOOK)
local LookLengths: buffer = buffer.create(SLOTS)
local LookVersions: buffer = buffer.create(SLOTS * 2)
local LookLives: buffer = buffer.create(SLOTS)
local Helds: buffer = buffer.create(SLOTS * MAX_HELD)
local HeldLengths: buffer = buffer.create(SLOTS)
local HeldVersions: buffer = buffer.create(SLOTS * 2)
local Invisible: buffer = buffer.create(SLOTS)

local Steps: Steps = {
	count = 0,
	carried = 0,
	capacity = STEP_START,
	slots = buffer.create(STEP_START * 2),
	kinds = buffer.create(STEP_START),
	places = {},
	data = buffer.create(STEP_START * FOOTSTEP_BYTES),
}

-- The run before's footsteps, kept by begin while a turn this run follows a run its viewer was left, for file to put
-- past this run's: each that fell while its slot's life was not Invisible, with that life and its kind. Beside them,
-- the Invisible marks as the run hush kept them for had them
local Carry: {
	count: number,
	capacity: number, -- The steps the buffers hold before they grow
	slots: buffer, -- u16
	kinds: buffer, -- u8: its kind's code from 1
	lives: buffer, -- u8: its slot's generation in the run it fell in
	bodies: buffer, -- u8: and its slot's kind code then
	places: { vector },
	data: buffer,
	marks: buffer, -- u8 by slot
	hushed: number, -- The run whose marks those are, 0 for none
	filed: number, -- The run file last filed, whose footsteps the world's buffers hold, 0 for none
} =
	{
		count = 0,
		capacity = 0,
		slots = buffer.create(0),
		kinds = buffer.create(0),
		lives = buffer.create(0),
		bodies = buffer.create(0),
		places = {},
		data = buffer.create(0),
		marks = buffer.create(SLOTS),
		hushed = 0,
		filed = 0,
	}

local World: World = {
	present = Present,
	generations = Generations,
	kinds = Kinds,
	unparked = Unparked,
	facings = Facings,
	positions = Radii.grid.positions,
	walk = Radii.grid.walk,
	records = Records,
	changed = Changed,
	history = buffer.create(0), -- About 2 MiB made at start, only while records go as changes
	looks = Looks,
	lookLengths = LookLengths,
	lookVersions = LookVersions,
	lookLives = LookLives,
	helds = Helds,
	heldLengths = HeldLengths,
	heldVersions = HeldVersions,
	invisible = Invisible,
	steps = Steps,
}

-- Records as changes, on while the game's relay.changes is: the run and wire tick each of the history's planes holds,
-- and this run's changes, each encoded once by slot and base for every view sharing that baseline, their buffers made
-- at start while it is on. Beside them, the base each record listed this turn goes against, 0 for whole, and the block
-- the taps are handed with every change expanded. One table, since Luau caps a chunk's locals
local Deltas: {
	on: boolean,
	runs: buffer, -- u32
	ticks: buffer, -- u16
	encoded: buffer, -- A record's bytes for each, by slot then base
	stamps: buffer, -- u32: the run each was encoded on, 0 for none
	lengths: buffer, -- u8: its bytes, 0 when its record must go whole
	bases: buffer, -- u8: by slot
	tapped: Block.Block,
} =
	{
		on = false,
		runs = buffer.create(DEPTH * 4),
		ticks = buffer.create(DEPTH * 2),
		encoded = buffer.create(0),
		stamps = buffer.create(0),
		lengths = buffer.create(0),
		bases = buffer.create(SLOTS),
		tapped = Block.new(),
	}

-- The block being filled for the viewer whose turn it is, and what its tick may still take
local Out: Block.Block = Block.new()
local Open: boolean = false
local Filled: number = 0 -- The open block's bytes
local Spent: number = 0 -- The viewer's bytes this tick, framing included
local Used: number? = nil -- Volt's count of its bytes over the last second, nil until its turn first needs room

-- Whiteoak TODO: Volt sends a buffer field whole, so each block goes in a buffer of its exact length, kept here
-- once per length and reused, at most 889 buffers and Volt's copy of each block, and more for the taps' expanded
-- blocks while a sink observes; a buffer field that takes a length would remove both, a Volt task if G3 shows the cost
local Outgoing: { [number]: buffer } = {}

-- Who the open block goes to: the viewer whose turn it is, then each moderator watching it, with the mask of their
-- bits, and the moderators alone, whom its withheld block goes to
local Recipients: { Key } = {}
local RecipientCount: number = 0
local RecipientMask: number = 0
local Watchers: { Key } = {}
local Copied: boolean = false -- Whether its turn has opened a block yet this run

-- The withheld block being filled for the viewer whose turn it is, which takes nothing of its budget
local WithheldOut: Block.Block = Block.new()
local WithheldOpen: boolean = false
local WithheldFilled: number = 0
local WithheldRecords: { number } = {}
local WithheldLooks: { number } = {}

local Watched: { View } = {} -- Every view with a watcher

-- The viewer's turn's lists, kept across turns, and each listed record's place in the queue, highest first, which
-- share one table since Luau caps a chunk's locals
local Lists: {
	hides: { number },
	reveals: { number },
	restyles: { number },
	floors: { number },
	fills: { number },
	rest: { number }, -- The fills of the players outside the viewer's crowd cap, placed after every other
	priorities: buffer, -- f64 by slot
} =
	{
		hides = {},
		reveals = {},
		restyles = {},
		floors = {},
		fills = {},
		rest = {},
		priorities = buffer.create(SLOTS * 8),
	}

-- The crowd cap's selection, kept across turns: a heap of the nearest candidates so far, its farthest at place 0, the
-- capping turn each slot was last a member on, and since start the turns that capped and the candidates they held out
local Crowd: { keys: buffer, slots: buffer, members: buffer, turns: number, rest: number } = {
	keys = buffer.create(SLOTS * 8), -- f64 by heap place: the candidate's key
	slots = buffer.create(SLOTS * 2), -- u16 by heap place: its slot
	members = buffer.create(SLOTS * 8), -- f64 by slot
	turns = 0,
	rest = 0,
}

local Views: { [Key]: View } = {}

-- The world the front fills, and the codes and flags it fills the world and reads a view by
local Turn = {
	world = World,
	KIND_CODES = KIND_CODES,
	SENT = SENT,
	OWN = OWN,
	WITHHELD = WITHHELD,
}

--[[
    Starts the core with the settings the front worked out and the ports it
    calls out through, and makes each kind's cells and, while records go as
    changes, the history and the changes' cache. It runs once
--]]

function Turn.start(settings: Settings, ports: Ports)
	Send = ports.send
	SendWithheld = ports.sendWithheld
	Heard = ports.heard
	Traffic = ports.traffic
	IsHidden = ports.isHidden
	Valid = ports.valid
	Observing = ports.observing
	Observes = ports.observes
	Relayed = ports.relayed
	TapWithheld = ports.withheld

	-- Each kind's cells are as wide as its reach, so more turns cover every occupied cell and skip the sort, but the
	-- sleepers' are half sleepers.radius, as the bodies their narrower cells skip outweigh that sort. None is so
	-- small that the play area holds more of them than there are slots
	local bound: number = Constants.PLAY_BOUND
	local smallest: number = 2 * bound / math.sqrt(SLOTS)
	local grid: Grid = Radii.grid

	for index: number, kind: Block.Kind in Block.KINDS do
		local radius: number = settings.leave
		if kind == "Npc" then
			radius = settings.npcs
		elseif kind == "Sleeper" then
			radius = settings.sleepers
		end

		local size: number = math.max(kind == "Sleeper" and radius / 2 or radius, smallest)
		local across: number = math.ceil(2 * bound / size)
		grid.cells[index] = {
			radius = radius,
			size = size,
			across = across,
			heads = buffer.create(across * across * 2),
			tails = buffer.create(across * across * 2),
			westmost = across,
			eastmost = -1,
			southmost = across,
			northmost = -1,
			west = 0,
			east = -1,
			south = 0,
			north = -1,
		}
	end

	RelayRate = settings.relayRate
	StillTicks = STILL_SECONDS * RelayRate
	Radii = {
		enter = settings.enter,
		leave = settings.leave,
		sleepers = settings.sleepers,
		npcs = settings.npcs,
		grid = grid,
	}
	OutOfViewRate = settings.outOfView
	WeightNear = settings.weightNear
	WeightFar = settings.weightFar
	WeightShooter = settings.weightShooter
	WeightCone = settings.weightCone
	ShotRate = settings.shotRate
	Soft = settings.soft
	Hard = settings.hard
	NpcNearSquared = settings.npcNearSquared
	NpcFarRate = settings.npcFarRate
	Earshot = settings.earshot
	Clock.on = settings.clocks == true

	-- The history and the changes' cache, about 4.6 MiB made once, only while records go as changes
	if settings.changes then
		Deltas.on = true
		World.history = buffer.create(DEPTH * SLOTS * RECORD_BYTES)
		Deltas.encoded = buffer.create(SLOTS * DEPTH * RECORD_BYTES)
		Deltas.stamps = buffer.create(SLOTS * DEPTH * 4)
		Deltas.lengths = buffer.create(SLOTS * DEPTH)
	end
end

--[[
    Makes the run's footstep buffers hold at least count steps, keeping the
    steps they hold, at least doubling them whenever they grow
--]]

function Turn.room(count: number)
	local steps: Steps = Steps
	if count <= steps.capacity then
		return
	end

	local capacity: number = math.max(count, steps.capacity * 2)
	local slots: buffer = buffer.create(capacity * 2)
	local kinds: buffer = buffer.create(capacity)
	local data: buffer = buffer.create(capacity * FOOTSTEP_BYTES)

	buffer.copy(slots, 0, steps.slots)
	buffer.copy(kinds, 0, steps.kinds)
	buffer.copy(data, 0, steps.data)

	steps.capacity = capacity
	steps.slots = slots
	steps.kinds = kinds
	steps.data = data
end

--[[
    Keeps the Invisible marks as the run begun last has them, once, before
    the first mark changes after it: the front's setInvisible and a
    worker's hand-in change them between runs, and the next run's begin
    judges the steps it carries from that run by that run's own marks
--]]

function Turn.hush()
	if Carry.hushed ~= Run then
		Carry.hushed = Run
		buffer.copy(Carry.marks, 0, Invisible)
	end
end

--[[
    Begins a run: its count, its relay tick unwrapped, the relay ticks since
    the run before, the tick its blocks carry and its bands, which its turns
    read as the table stands, its turns' clocks from 0 while they are on,
    and while records go as changes, the history's plane its records go in.
    With carry, a turn this run follows a run its viewer was left, so the
    run before's footsteps, still in the buffers, are kept for file, but
    for each that fell while its slot's life was Invisible, which no one
    hears

    @ carry | whether to keep them, false or nil to keep none
--]]

function Turn.begin(run: number, tick: number, elapsed: number, wire: number, tuning: Tuning, carry: boolean?)
	Run = run
	RunTick = tick
	Elapsed = elapsed
	TickWire = wire
	Tune = tuning

	if Clock.on then
		buffer.fill(Clock.laps, 0, 0)
	end

	Steps.carried = 0
	Carry.count = 0
	if carry then
		local count: number = Steps.count
		if count > Carry.capacity then
			Carry.capacity = count
			Carry.slots = buffer.create(count * 2)
			Carry.kinds = buffer.create(count)
			Carry.lives = buffer.create(count)
			Carry.bodies = buffer.create(count)
			Carry.data = buffer.create(count * FOOTSTEP_BYTES)
		end

		-- The world still holds the run before's lives and kinds, and its Invisible marks too unless one changed since
		-- that run began, when hush kept them
		local marks: buffer = Carry.hushed == run - 1 and Carry.marks or Invisible
		local stepSlots: buffer = Steps.slots
		local kept: number = 0

		for index: number = 0, count - 1 do
			local slot: number = buffer.readu16(stepSlots, index * 2)
			local life: number = buffer.readu8(Generations, slot)

			if buffer.readu8(marks, slot) ~= life + 1 then
				buffer.writeu16(Carry.slots, kept * 2, slot)
				buffer.writeu8(Carry.kinds, kept, buffer.readu8(Steps.kinds, index))
				buffer.writeu8(Carry.lives, kept, life)
				buffer.writeu8(Carry.bodies, kept, buffer.readu8(Kinds, slot))
				buffer.copy(Carry.data, kept * FOOTSTEP_BYTES, Steps.data, index * FOOTSTEP_BYTES, FOOTSTEP_BYTES)
				kept += 1
				Carry.places[kept] = Steps.places[index + 1]
			end
		end

		Carry.count = kept
	end

	-- The plane names the run and its tick for every change against its records
	if Deltas.on then
		local plane: number = run % DEPTH
		buffer.writeu32(Deltas.runs, plane * 4, run)
		buffer.writeu16(Deltas.ticks, plane * 2, wire)
	end
end

--[[
    Files each of the count bodies the front walked this run in its cell's
    list in its kind's cells, in the order the states were walked, which
    each turn keeps, held to the grid's edges, and a NaN place to its first
    cell, since a turn finds that inside no radius. The footsteps begin
    kept go past this run's, as its carried steps, each whose slot holds
    the life and kind it fell in, so a viewer's flags this run judge the
    body that took it. A slot absent this run still holds its last life and
    kind, so its steps go past too, unheard, since it is culled from no one.
    The run is then the one filed
--]]

function Turn.file(count: number)
	local carried: number = Carry.count
	if carried > 0 then
		local from: number = Steps.count
		Turn.room(from + carried)

		local stepSlots: buffer = Steps.slots
		local stepKinds: buffer = Steps.kinds
		local stepData: buffer = Steps.data
		local at: number = from

		for index: number = 0, carried - 1 do
			local slot: number = buffer.readu16(Carry.slots, index * 2)

			if
				buffer.readu8(Generations, slot) == buffer.readu8(Carry.lives, index)
				and buffer.readu8(Kinds, slot) == buffer.readu8(Carry.bodies, index)
			then
				buffer.writeu16(stepSlots, at * 2, slot)
				buffer.writeu8(stepKinds, at, buffer.readu8(Carry.kinds, index))
				buffer.copy(stepData, at * FOOTSTEP_BYTES, Carry.data, index * FOOTSTEP_BYTES, FOOTSTEP_BYTES)
				at += 1
				Steps.places[at] = Carry.places[index + 1]
			end
		end

		Steps.carried = at - from
	end

	local grid: Grid = Radii.grid
	local positions: { vector } = grid.positions
	local walkOrder: buffer = grid.walk
	local bound: number = Constants.PLAY_BOUND

	for _, cells: Cells in grid.cells do
		buffer.fill(cells.heads, 0, 0)
		cells.westmost = cells.across
		cells.eastmost = -1
		cells.southmost = cells.across
		cells.northmost = -1
		cells.east = -1
		cells.north = -1
	end

	for order: number = 1, count do
		local slot: number = buffer.readu16(walkOrder, order * 2)
		local position: vector = positions[slot + 1]

		local cells: Cells = grid.cells[buffer.readu8(Kinds, slot) + 1]
		local size: number = cells.size
		local across: number = cells.across
		local column: number = (position.x + bound) // size
		local row: number = (position.z + bound) // size
		column = column >= 0 and math.min(column, across - 1) or 0
		row = row >= 0 and math.min(row, across - 1) or 0

		local cell: number = (row * across + column) * 2
		if buffer.readu16(cells.heads, cell) == 0 then
			buffer.writeu16(cells.heads, cell, slot + 1)
		else
			buffer.writeu16(grid.following, buffer.readu16(cells.tails, cell) * 2, slot + 1)
		end

		buffer.writeu16(cells.tails, cell, slot)
		buffer.writeu16(grid.following, slot * 2, 0)
		buffer.writeu16(grid.columns, slot * 2, column)
		buffer.writeu16(grid.rows, slot * 2, row)
		buffer.writeu16(grid.orders, slot * 2, order)

		if column < cells.westmost then
			cells.westmost = column
		end

		if column > cells.eastmost then
			cells.eastmost = column
		end

		if row < cells.southmost then
			cells.southmost = row
		end

		if row > cells.northmost then
			cells.northmost = row
		end
	end

	grid.count = count
	Carry.filed = Run
end

-- The run Turn.file last filed, whose footsteps the buffers hold, 0 before the first
function Turn.filed(): number
	return Carry.filed
end

-- Whether a slot's look is set for its current life
local function dressed(slot: number): boolean
	return buffer.readu8(LookLives, slot) == buffer.readu8(Generations, slot) + 1
end

-- Both parts of a slot's look pending afresh for a viewer, the look only once one is set for the slot's life
local function lookAgain(view: View, slot: number, flags: number): number
	flags = bit32.bor(bit32.band(flags, bit32.bnot(LOOKS)), HELD)
	if dressed(slot) then
		flags = bit32.bor(flags, LOOK)
	end

	buffer.writeu16(view.lookSent, slot * 2, buffer.readu16(LookVersions, slot * 2))
	buffer.writeu16(view.heldSent, slot * 2, buffer.readu16(HeldVersions, slot * 2))

	return flags
end

-- Whether a part's version moved on since it was last given out, marking the latest given
local function moved(sent: buffer, versions: buffer, slot: number): boolean
	local version: number = buffer.readu16(versions, slot * 2)
	if version == buffer.readu16(sent, slot * 2) then
		return false
	end

	buffer.writeu16(sent, slot * 2, version)

	return true
end

-- Each part of a slot's look pending again, its latest, when it changed since the viewer was last given it
local function restyle(view: View, slot: number, flags: number): number
	if moved(view.lookSent, LookVersions, slot) and dressed(slot) then
		flags = bit32.bor(bit32.band(flags, bit32.bnot(LOOK_CARRIED)), LOOK)
	end

	if moved(view.heldSent, HeldVersions, slot) then
		flags = bit32.bor(bit32.band(flags, bit32.bnot(HELD_CARRIED)), HELD)
	end

	return flags
end

-- A fresh pending reveal of the slot's current kind, with both parts of its look in the same block
local function revealAgain(view: View, slot: number, flags: number): number
	buffer.writeu8(view.kinds, slot, buffer.readu8(Kinds, slot))

	-- Its record rides with the reveal, so nothing is owed for a stretch held to the out-of-view rate before it
	local revealed: number = bit32.bor(bit32.band(flags, bit32.bnot(HIDE + VISIBILITY_CARRIED + OUTSIDE)), REVEAL)

	return lookAgain(view, slot, revealed)
end

--[[
    Moves a pair's stretch toward what the viewer should be sent: a reveal
    when it starts, changes kind or follows a hide that left, a hide when
    it ends, and the look's changes while it lasts. A reveal or a hide that
    never rode a block is taken back instead
--]]

local function settle(view: View, slot: number, flags: number, wanted: boolean, generation: number): number
	if wanted then
		buffer.writeu8(view.generations, slot, generation)

		if bit32.btest(flags, HIDE) then
			if bit32.btest(flags, VISIBILITY_CARRIED) then
				return revealAgain(view, slot, flags)
			end

			-- The hide never left, so the viewer was sent the character all along
			flags = bit32.band(flags, bit32.bnot(HIDE))
		end

		if not bit32.btest(flags, SENT + REVEAL) or buffer.readu8(view.kinds, slot) ~= buffer.readu8(Kinds, slot) then
			return revealAgain(view, slot, flags)
		end

		return restyle(view, slot, flags)
	end

	-- A hide rides on until it is acknowledged. Until it first leaves, the look waits with it in case it is taken
	-- back, and once it has left, the next reveal carries the whole look
	if bit32.btest(flags, HIDE) then
		if bit32.btest(flags, SENT) then
			return flags
		end

		return bit32.band(flags, bit32.bnot(LOOKS))
	end

	if bit32.btest(flags, SENT) then
		return bit32.bor(bit32.band(flags, bit32.bnot(REVEAL + VISIBILITY_CARRIED)), HIDE)
	end

	return bit32.band(flags, bit32.bnot(REVEAL + VISIBILITY_CARRIED + LOOKS))
end

-- Adds a slot to the ones a viewer holds anything for, starting its record timing afresh
local function track(view: View, slot: number)
	if buffer.readu16(view.places, slot * 2) ~= 0 then
		return
	end

	local tracked: { number } = view.tracked
	table.insert(tracked, slot)

	buffer.writeu16(view.places, slot * 2, #tracked)
	buffer.writeu8(view.repeats, slot, 0)
	buffer.writeu32(view.lastRecord, slot * 4, 0)
	buffer.writef32(view.aim, slot * 4, 0)
	buffer.writef32(view.floor, slot * 4, 0)
end

-- Takes a slot a viewer holds nothing more for out of its list, by moving the list's last slot into its place
local function untrack(view: View, slot: number)
	local tracked: { number } = view.tracked
	local place: number = buffer.readu16(view.places, slot * 2)
	local last: number = tracked[#tracked]

	tracked[place] = last
	buffer.writeu16(view.places, last * 2, place)
	tracked[#tracked] = nil

	buffer.writeu16(view.places, slot * 2, 0)
	buffer.writeu16(view.flags, slot * 2, 0)

	local withheld: Withheld? = view.withheld
	if withheld then
		buffer.writeu8(withheld.flags, slot, 0)
	end
end

--[[
    Clears one pending entry a block carried, once the viewer acknowledged
    it, unless the entry changed after that block, so a newer one waits
    for an acknowledgment of its own
--]]

local function clear(view: View, slot: number, part: number, sequence: number)
	if part == WITHHELD_LOOK_PART or part == WITHHELD_HELD_PART then
		local withheld: Withheld? = view.withheld
		if not withheld then
			return
		end

		local mark: number = buffer.readu8(withheld.flags, slot)
		if part == WITHHELD_LOOK_PART then
			if
				bit32.btest(mark, WITHHELD_LOOK_CARRIED)
				and Sequence.difference(sequence, buffer.readu16(withheld.lookFrom, slot * 2)) >= 0
			then
				mark = bit32.band(mark, bit32.bnot(WITHHELD_LOOK + WITHHELD_LOOK_CARRIED))
			end
		elseif
			bit32.btest(mark, WITHHELD_HELD_CARRIED)
			and Sequence.difference(sequence, buffer.readu16(withheld.heldFrom, slot * 2)) >= 0
		then
			mark = bit32.band(mark, bit32.bnot(WITHHELD_HELD + WITHHELD_HELD_CARRIED))
		end

		buffer.writeu8(withheld.flags, slot, mark)

		return
	end

	local flags: number = buffer.readu16(view.flags, slot * 2)

	if part == VISIBILITY then
		local from: number = buffer.readu16(view.visibilityFrom, slot * 2)
		if bit32.btest(flags, VISIBILITY_CARRIED) and Sequence.difference(sequence, from) >= 0 then
			flags = bit32.band(flags, bit32.bnot(REVEAL + HIDE + VISIBILITY_CARRIED))
		end
	elseif part == LOOK_PART then
		if
			bit32.btest(flags, LOOK_CARRIED)
			and Sequence.difference(sequence, buffer.readu16(view.lookFrom, slot * 2)) >= 0
		then
			flags = bit32.band(flags, bit32.bnot(LOOK + LOOK_CARRIED))
		end
	elseif
		bit32.btest(flags, HELD_CARRIED)
		and Sequence.difference(sequence, buffer.readu16(view.heldFrom, slot * 2)) >= 0
	then
		flags = bit32.band(flags, bit32.bnot(HELD + HELD_CARRIED))
	end

	buffer.writeu16(view.flags, slot * 2, flags)
end

--[[
    Clears what one remembered block carried, once every recipient it went
    to has acknowledged it, and makes each record it carried from the view's
    floor on its slot's baseline, when newer than the one before
--]]

local function discharge(view: View, ring: number)
	local sequence: number = buffer.readu32(view.ringSequences, ring * 4) - 1
	local run: number = buffer.readu32(view.ringRuns, ring * 4)
	buffer.writeu32(view.ringSequences, ring * 4, 0)

	-- Entries the log has since written over ride on until a later block's acknowledgment clears them
	local start: number = buffer.readf64(view.ringStarts, ring * 8)
	if view.logHead - start > LOG then
		return
	end

	local log: buffer = view.log
	local baseRuns: buffer = view.baseRuns
	local baseFloor: number = view.baseFloor

	for index: number = start, start + buffer.readu16(view.ringCounts, ring * 2) - 1 do
		local code: number = buffer.readu16(log, (index % LOG) * 2)
		local slot: number = code // ENTRY_PARTS
		local part: number = code - slot * ENTRY_PARTS

		if part ~= RECORD_PART then
			clear(view, slot, part, sequence)
		elseif run >= baseFloor and run > buffer.readu32(baseRuns, slot * 4) then
			buffer.writeu32(baseRuns, slot * 4, run)
		end
	end
end

-- One recipient's acknowledgment of a block, its bit in the block's mask, which counts once and only for a block
-- that went to it
local function receipt(view: View, sequence: number, bit: number)
	local ring: number = sequence % RING
	if buffer.readu32(view.ringSequences, ring * 4) ~= sequence + 1 then
		return
	end

	local owed: number = buffer.readu32(view.ringOwed, ring * 4)
	if not bit32.btest(owed, bit) then
		return
	end

	owed = bit32.band(owed, bit32.bnot(bit))
	buffer.writeu32(view.ringOwed, ring * 4, owed)

	if owed == 0 then
		discharge(view, ring)
	end
end

-- Takes in one recipient's acknowledgment: its newest sequence, 0 for none, and the mask of the 16 before it
local function acknowledge(view: View, newest: number, mask: number, bit: number)
	if newest ~= 0 then
		receipt(view, newest, bit)
	end

	for back: number = 1, Constants.ACK_MASK_BITS do
		if bit32.btest(mask, 2 ^ (back - 1)) then
			receipt(view, (newest - back) % WRAP, bit)
		end
	end
end

-- Numbers a view's next block past latest, the newest block a watcher's client was sent elsewhere, so an
-- acknowledgment its client still makes of those can never name one of the view's own
local function renumber(view: View, latest: number)
	if latest ~= 0 and Sequence.difference(view.sequence, latest) <= 0 then
		view.sequence = latest % SEQUENCES + Constants.FIRST_SEQUENCE
	end
end

-- Opens a viewer's next block of the tick, with the ring entry its recipients' acknowledgments will name
local function open(view: View)
	local sequence: number = view.sequence
	local ring: number = sequence % RING

	view.sequence = sequence % SEQUENCES + Constants.FIRST_SEQUENCE
	view.newest = sequence
	Copied = true

	Out.sequence = sequence
	Out.tick = TickWire
	Out.revealCount = 0
	Out.hideCount = 0
	Out.lookCount = 0
	Out.footstepCount = 0
	Out.recordCount = 0
	Out.changeCount = 0
	Out.footstepData = Steps.data
	Out.recordData = Records
	Out.changeData = Deltas.encoded

	buffer.writeu32(view.ringSequences, ring * 4, sequence + 1)
	buffer.writeu32(view.ringRuns, ring * 4, Run)
	buffer.writef64(view.ringStarts, ring * 8, view.logHead)
	buffer.writeu16(view.ringCounts, ring * 2, 0)
	buffer.writeu32(view.ringOwed, ring * 4, RecipientMask)

	Open = true
	Filled = HEADER_BYTES
	Spent += HEADER_BYTES + FRAME_BYTES
end

-- The buffer a block of exactly length bytes goes in, made the first time that length is sent
local function exact(length: number): buffer
	local kept: buffer? = Outgoing[length]
	if kept then
		return kept
	end

	local made: buffer = buffer.create(length)
	Outgoing[length] = made

	return made
end

--[[
    Writes the open block into the buffer of its exact length and sends it
    to its viewer and every watcher at once. While a sink observes one of
    them, the taps are handed it with each change expanded to the whole
    record it decodes to, its slot's record this run, so a clip never
    needs a baseline and its block may pass 896 B
--]]

local function flush()
	if not Open then
		return
	end

	Open = false

	local data: buffer = exact(Filled)
	if Block.write(Out, data) ~= Filled then
		error("A relay block wrote other than the bytes the relay counted for it")
	end

	Send(Recipients, data)

	-- Only a block whose recipients a sink observes goes in a frame, so only such a block's changes are expanded
	local observing: boolean = Observing()
	if observing and Out.changeCount == 0 then
		Relayed(Recipients, RecipientCount, Out, data)
	elseif observing and Observes(Recipients, RecipientCount) then
		local tapped: Block.Block = Deltas.tapped
		local records: { number } = tapped.records
		local count: number = Out.recordCount
		local length: number = Filled

		table.move(Out.records, 1, count, 1, records)

		for index: number = 1, Out.changeCount do
			count += 1
			records[count] = (buffer.readu16(Out.changeData, Out.changeOffsets[index]) % SLOTS) * RECORD_BYTES
			length += RECORD_BYTES - Out.changeLengths[index]
		end

		tapped.sequence = Out.sequence
		tapped.tick = Out.tick
		tapped.revealCount = Out.revealCount
		tapped.reveals = Out.reveals
		tapped.hideCount = Out.hideCount
		tapped.hides = Out.hides
		tapped.lookCount = Out.lookCount
		tapped.looks = Out.looks
		tapped.footstepCount = Out.footstepCount
		tapped.footsteps = Out.footsteps
		tapped.footstepData = Out.footstepData
		tapped.recordCount = count
		tapped.recordData = Records

		-- The sent block's buffer may be this one, which Volt has already copied
		local expanded: buffer = exact(length)
		if Block.write(tapped, expanded, Constants.TAP_BLOCK_BYTES) ~= length then
			error("A tap block wrote other than the bytes the relay counted for it")
		end

		Relayed(Recipients, RecipientCount, tapped, expanded)
	end

	Heard(Recipients, RecipientCount, Out.sequence)
end

--[[
    Makes room for an entry of bytes in a section holding count entries:
    in the open block, or a fresh one when it would pass 896 B or its count,
    so long as the viewer's tick stays inside its room under a budget in
    bytes a second, Hard for what is owed and Soft for the rest. False
    leaves both as they were
--]]

local function fits(view: View, bytes: number, count: number, budget: number): boolean
	local fresh: boolean = not Open or Filled + bytes > BLOCK_BYTES or count >= SECTION_LIMIT
	local cost: number = bytes
	if fresh then
		cost += HEADER_BYTES + FRAME_BYTES
	end

	-- A tick's room is its share of the budget and never more than the last second left, Volt's count of which is
	-- read the first time the turn needs room
	local used: number = Used or Traffic(view.key)
	Used = used

	if Spent + cost > math.min(budget / RelayRate, budget - used) then
		return false
	end

	if fresh then
		flush()
		open(view)
	end

	Filled += bytes
	Spent += bytes

	return true
end

--[[
    Logs a pending entry under the view's newest block, which carries it or
    goes beside the withheld block that does, marking where it first rode
    since it last changed
--]]

local function carry(view: View, slot: number, part: number, flags: number, carried: number, from: buffer): number
	local sequence: number = view.newest
	if not bit32.btest(flags, carried) then
		buffer.writeu16(from, slot * 2, sequence)
		flags = bit32.bor(flags, carried)
	end

	local ring: number = (sequence % RING) * 2
	buffer.writeu16(view.log, (view.logHead % LOG) * 2, slot * ENTRY_PARTS + part)
	buffer.writeu16(view.ringCounts, ring, buffer.readu16(view.ringCounts, ring) + 1)
	view.logHead += 1

	return flags
end

-- The bytes a look entry takes with the parts named present
local function entryBytes(slot: number, look: boolean, held: boolean): number
	local bytes: number = Constants.LOOK_ENTRY_BYTES

	if look then
		bytes += Constants.PREFIX_BYTES + buffer.readu8(LookLengths, slot)
	end

	if held then
		bytes += Constants.PREFIX_BYTES + buffer.readu8(HeldLengths, slot)
	end

	return bytes
end

-- The bytes a look entry takes with the parts pending
local function lookBytes(slot: number, flags: number): number
	return entryBytes(slot, bit32.btest(flags, LOOK), bit32.btest(flags, HELD))
end

-- A block's look entry at count, its table made the first time the block holds that many, as are the others
local function lookEntry(block: Block.Block, count: number): Block.Look
	local kept: Block.Look? = block.looks[count]
	if kept then
		return kept
	end

	local made: Block.Look = {
		slot = 0,
		generation = 0,
		look = false,
		lookData = Looks,
		lookAt = 0,
		lookLength = 0,
		held = false,
		heldData = Helds,
		heldAt = 0,
		heldLength = 0,
	}
	block.looks[count] = made

	return made
end

local function hideEntry(count: number): Block.Hide
	local kept: Block.Hide? = Out.hides[count]
	if kept then
		return kept
	end

	local made: Block.Hide = { slot = 0, generation = 0, culled = false }
	Out.hides[count] = made

	return made
end

local function revealEntry(count: number): Block.Reveal
	local kept: Block.Reveal? = Out.reveals[count]
	if kept then
		return kept
	end

	local made: Block.Reveal = { slot = 0, generation = 0, kind = "Player" }
	Out.reveals[count] = made

	return made
end

-- Puts a slot's look entry with the parts named into a block, which has room for it
local function fillLook(block: Block.Block, slot: number, look: boolean, held: boolean)
	local count: number = block.lookCount + 1
	local entry: Block.Look = lookEntry(block, count)

	entry.slot = slot
	entry.generation = buffer.readu8(Generations, slot)
	entry.look = look
	entry.lookData = Looks
	entry.lookAt = slot * MAX_LOOK
	entry.lookLength = buffer.readu8(LookLengths, slot)
	entry.held = held
	entry.heldData = Helds
	entry.heldAt = slot * MAX_HELD
	entry.heldLength = buffer.readu8(HeldLengths, slot)
	block.lookCount = count
end

-- Puts a look entry with the parts pending into the open block, which has room for it
local function writeLook(view: View, slot: number, flags: number): number
	local look: boolean = bit32.btest(flags, LOOK)
	local held: boolean = bit32.btest(flags, HELD)
	fillLook(Out, slot, look, held)

	if look then
		flags = carry(view, slot, LOOK_PART, flags, LOOK_CARRIED, view.lookFrom)
	end

	if held then
		flags = carry(view, slot, HELD_PART, flags, HELD_CARRIED, view.heldFrom)
	end

	return flags
end

--[[
    Puts a slot's record into the open block, which has room for it, whole
    for a base of 0 and otherwise as its change against that base, encoded
    this run, and times its next one from now. While records go as changes
    it is logged, so the block's acknowledgment makes it a baseline
--]]

local function writeRecord(view: View, slot: number, base: number)
	if base == 0 then
		local count: number = Out.recordCount + 1
		Out.records[count] = slot * RECORD_BYTES
		Out.recordCount = count
	else
		local entry: number = slot * DEPTH + base
		local count: number = Out.changeCount + 1
		Out.changeOffsets[count] = entry * RECORD_BYTES
		Out.changeLengths[count] = buffer.readu8(Deltas.lengths, entry)
		Out.changeCount = count
	end

	if Deltas.on then
		local ring: number = (view.newest % RING) * 2
		local ringCounts: buffer = view.ringCounts
		local logHead: number = view.logHead
		buffer.writeu16(view.log, (logHead % LOG) * 2, slot * ENTRY_PARTS + RECORD_PART)
		buffer.writeu16(ringCounts, ring, buffer.readu16(ringCounts, ring) + 1)
		view.logHead = logHead + 1
	end

	local lastRecord: buffer = view.lastRecord
	local repeats: buffer = view.repeats
	local last: number = buffer.readu32(lastRecord, slot * 4)
	if buffer.readu32(Changed, slot * 4) > last then
		buffer.writeu8(repeats, slot, REST_REPEATS)
	else
		local left: number = buffer.readu8(repeats, slot)
		if left > 0 then
			buffer.writeu8(repeats, slot, left - 1)
		end
	end

	local aims: buffer = view.aim
	local floors: buffer = view.floor
	buffer.writeu32(lastRecord, slot * 4, RunTick)
	buffer.writef32(aims, slot * 4, math.max(buffer.readf32(aims, slot * 4) - 1, 0))
	buffer.writef32(floors, slot * 4, math.max(buffer.readf32(floors, slot * 4) - 1, 0))
end

local function addHide(view: View, slot: number)
	if not fits(view, HIDE_BYTES, Out.hideCount, Hard) then
		return
	end

	local count: number = Out.hideCount + 1
	local hide: Block.Hide = hideEntry(count)
	local flags: number = buffer.readu16(view.flags, slot * 2)

	-- Each copy of a pending hide says whether anti-ESP hides the pair this run
	hide.slot = slot
	hide.generation = buffer.readu8(view.generations, slot)
	hide.culled = bit32.btest(flags, CULLED)
	Out.hideCount = count

	-- The viewer stops being sent the character the tick its hide is first carried
	flags = carry(view, slot, VISIBILITY, flags, VISIBILITY_CARRIED, view.visibilityFrom)
	buffer.writeu16(view.flags, slot * 2, bit32.band(flags, bit32.bnot(SENT)))
end

-- A reveal, its look entry and its whole record, all in one block or not at all
local function addReveal(view: View, slot: number)
	local flags: number = buffer.readu16(view.flags, slot * 2)
	local dressing: boolean = bit32.btest(flags, LOOK + HELD)

	local bytes: number = REVEAL_BYTES + RECORD_BYTES
	if dressing then
		bytes += lookBytes(slot, flags)
	end

	if not fits(view, bytes, math.max(Out.revealCount, Out.lookCount), Hard) then
		return
	end

	local count: number = Out.revealCount + 1
	local reveal: Block.Reveal = revealEntry(count)

	reveal.slot = slot
	reveal.generation = buffer.readu8(Generations, slot)
	reveal.kind = Block.KINDS[buffer.readu8(view.kinds, slot) + 1]
	Out.revealCount = count

	if dressing then
		flags = writeLook(view, slot, flags)
	end

	writeRecord(view, slot, 0)

	-- The viewer is sent the character from the tick its reveal is first carried
	flags = carry(view, slot, VISIBILITY, flags, VISIBILITY_CARRIED, view.visibilityFrom)
	buffer.writeu16(view.flags, slot * 2, bit32.bor(flags, SENT))
end

local function addLook(view: View, slot: number)
	local flags: number = buffer.readu16(view.flags, slot * 2)
	if fits(view, lookBytes(slot, flags), Out.lookCount, Hard) then
		buffer.writeu16(view.flags, slot * 2, writeLook(view, slot, flags))
	end
end

local function addFootstep(view: View, offset: number)
	if not fits(view, FOOTSTEP_BYTES, Out.footstepCount, Hard) then
		return
	end

	local count: number = Out.footstepCount + 1
	Out.footsteps[count] = offset
	Out.footstepCount = count
end

--[[
    Adds the run's footsteps from first to last, by their index in its
    steps, that the viewer hears: each of an enemy its flags hold culled and
    not sent this turn, inside the step's range of where it stands now
--]]

local function listen(view: View, origin: vector, first: number, last: number)
	local viewFlags: buffer = view.flags
	local steps: Steps = Steps
	local stepSlots: buffer = steps.slots
	local stepKinds: buffer = steps.kinds
	local stepPlaces: { vector } = steps.places

	for index: number = first, last do
		local slot: number = buffer.readu16(stepSlots, index * 2)
		local flags: number = buffer.readu16(viewFlags, slot * 2)

		if bit32.btest(flags, CULLED) and not bit32.btest(flags, SENT) then
			local offset: vector = stepPlaces[index + 1] - origin
			if vector.dot(offset, offset) <= Earshot[buffer.readu8(stepKinds, index)] then
				addFootstep(view, index * FOOTSTEP_BYTES)
			end
		end
	end
end

-- The higher of two listed records' places in the queue
local function ahead(a: number, b: number): boolean
	local priorities: buffer = Lists.priorities

	return buffer.readf64(priorities, a * 8) > buffer.readf64(priorities, b * 8)
end

-- Takes the stale entries past count off the end of a list a turn refilled, so it is exactly that long
local function trim<T>(list: { T }, count: number)
	local index: number = count + 1
	while list[index] ~= nil do
		list[index] = nil
		index += 1
	end
end

--[[
    Places a list's records inside the tick's room under a budget, as fits
    finds it, highest in the queue first when they can't all fit, each whole
    or as its change, prepared first so the sort knows their sizes, and
    stops at the first that doesn't fit. Those left keep at most one band
    tick owed. An empty list needs no room
--]]

local function placeRecords(view: View, list: { number }, count: number, budget: number)
	trim(list, count)
	if count == 0 then
		return
	end

	local on: boolean = Deltas.on
	local baseRuns: buffer = view.baseRuns
	local baseFloor: number = view.baseFloor
	local runs: buffer = Deltas.runs
	local ticks: buffer = Deltas.ticks
	local stamps: buffer = Deltas.stamps
	local lengths: buffer = Deltas.lengths
	local bases: buffer = Deltas.bases
	local wholes: number, changeBytes: number = 0, 0

	-- Each record's base as a change this run, 0 for whole: its baseline is the newest record of its life every
	-- recipient of the view acknowledged from the view's floor on, 1 to 31 relay ticks back, and its change is encoded
	-- once a run for each slot and base, so every view sharing that baseline copies the same bytes. X or Z moved past
	-- what a change holds sends it whole
	for index: number = 1, count do
		local slot: number = list[index]
		local base: number = 0
		local baseRun: number = 0
		if on then
			baseRun = buffer.readu32(baseRuns, slot * 4)
		end

		local plane: number = baseRun % DEPTH
		if
			baseRun ~= 0
			and baseRun >= baseFloor
			and Run - baseRun < DEPTH
			and buffer.readu32(runs, plane * 4) == baseRun
		then
			local back: number = (TickWire - buffer.readu16(ticks, plane * 2)) % WRAP
			local entry: number = slot * DEPTH + back

			if back >= 1 and back < DEPTH then
				if buffer.readu32(stamps, entry * 4) ~= Run then
					local baseline: number = (plane * SLOTS + slot) * RECORD_BYTES
					local length: number = Change.write(
						Records,
						slot * RECORD_BYTES,
						World.history,
						baseline,
						back,
						Deltas.encoded,
						entry * RECORD_BYTES
					)

					buffer.writeu32(stamps, entry * 4, Run)
					buffer.writeu8(lengths, entry, length)
				end

				if buffer.readu8(lengths, entry) ~= 0 then
					base = back
				end
			end
		end

		buffer.writeu8(bases, slot, base)

		if base == 0 then
			wholes += 1
		else
			changeBytes += buffer.readu8(lengths, slot * DEPTH + base)
		end
	end

	local used: number = Used or Traffic(view.key)
	local room: number = math.min(budget / RelayRate, budget - used)
	Used = used

	local blocks: number = wholes // Constants.MAX_RELAY_RECORDS + changeBytes // (BLOCK_BYTES - HEADER_BYTES) + 1
	if Spent + wholes * RECORD_BYTES + changeBytes + blocks * (HEADER_BYTES + FRAME_BYTES) > room then
		table.sort(list, ahead)
	end

	local records: { number } = Out.records
	local changeOffsets: { number } = Out.changeOffsets
	local changeLengths: { number } = Out.changeLengths
	local log: buffer = view.log
	local ringCounts: buffer = view.ringCounts
	local lastRecord: buffer = view.lastRecord
	local repeats: buffer = view.repeats
	local aims: buffer = view.aim
	local floors: buffer = view.floor

	-- Whiteoak TODO: placing stops at the first record that doesn't fit, though a smaller change later in the queue
	-- could have; skip on to the next that fits, a pass over the rest, once G4 shows records cut beside unused room
	for index: number = 1, count do
		local slot: number = list[index]
		local base: number = buffer.readu8(bases, slot)
		local entry: number = slot * DEPTH + base
		local bytes: number = RECORD_BYTES
		if base ~= 0 then
			bytes = buffer.readu8(lengths, entry)
		end

		-- Room in the open block is taken as fits takes it, and only a fresh block or a refusal goes through fits
		if Open and Filled + bytes <= BLOCK_BYTES and Spent + bytes <= room then
			Filled += bytes
			Spent += bytes
		elseif not fits(view, bytes, 0, budget) then
			RecordsCut += count - index + 1
			break
		end

		-- Each goes in as writeRecord puts a reveal's in: whole or as its change, logged while records go as
		-- changes, and its next one timed from now
		if base == 0 then
			local placed: number = Out.recordCount + 1
			records[placed] = slot * RECORD_BYTES
			Out.recordCount = placed
		else
			local placed: number = Out.changeCount + 1
			changeOffsets[placed] = entry * RECORD_BYTES
			changeLengths[placed] = bytes
			Out.changeCount = placed
		end

		if on then
			local ring: number = (view.newest % RING) * 2
			local logHead: number = view.logHead
			buffer.writeu16(log, (logHead % LOG) * 2, slot * ENTRY_PARTS + RECORD_PART)
			buffer.writeu16(ringCounts, ring, buffer.readu16(ringCounts, ring) + 1)
			view.logHead = logHead + 1
		end

		local last: number = buffer.readu32(lastRecord, slot * 4)
		if buffer.readu32(Changed, slot * 4) > last then
			buffer.writeu8(repeats, slot, REST_REPEATS)
		else
			local left: number = buffer.readu8(repeats, slot)
			if left > 0 then
				buffer.writeu8(repeats, slot, left - 1)
			end
		end

		buffer.writeu32(lastRecord, slot * 4, RunTick)
		buffer.writef32(aims, slot * 4, math.max(buffer.readf32(aims, slot * 4) - 1, 0))
		buffer.writef32(floors, slot * 4, math.max(buffer.readf32(floors, slot * 4) - 1, 0))
		RecordsSent += 1
	end

	for index: number = 1, count do
		local slot: number = list[index]
		if buffer.readu32(lastRecord, slot * 4) ~= RunTick then
			buffer.writef32(aims, slot * 4, math.min(buffer.readf32(aims, slot * 4), 1))
			buffer.writef32(floors, slot * 4, math.min(buffer.readf32(floors, slot * 4), 1))
		end
	end
end

-- The viewer's own character: no reveal or record, and a look entry when it is made and on each change
local function claim(view: View, own: number?)
	local previous: number? = view.own
	if previous ~= nil and previous ~= own then
		local flags: number = buffer.readu16(view.flags, previous * 2)
		buffer.writeu16(view.flags, previous * 2, bit32.band(flags, bit32.bnot(OWN + LOOKS)))
	end

	view.own = own

	if own == nil or buffer.readu32(Present, own * 4) ~= Run then
		return
	end

	local flags: number = bit32.band(buffer.readu16(view.flags, own * 2), bit32.bnot(RELEVANT + EDGES + CULLED))
	flags = bit32.band(flags, bit32.bnot(SENT + REVEAL + HIDE + VISIBILITY_CARRIED))

	local generation: number = buffer.readu8(Generations, own)
	if bit32.btest(flags, OWN) and buffer.readu8(view.generations, own) == generation then
		flags = restyle(view, own, flags)
	else
		buffer.writeu8(view.generations, own, generation)
		flags = lookAgain(view, own, bit32.bor(flags, OWN))
	end

	track(view, own)
	buffer.writeu16(view.flags, own * 2, flags)
end

-- Adds the seconds since the part being timed began to that part of the run's turns, and begins the next part
local function lapped(part: number)
	local now: number = os.clock()
	local at: number = part * 8
	buffer.writef64(Clock.laps, at, buffer.readf64(Clock.laps, at) + now - Clock.from)
	Clock.from = now
end

--[[
    Every other present body against the viewer that the run could change:
    those in the cells its kind's reach spans, the lesser of the kind's
    radius and the viewer's distance, and each it holds anything for
    elsewhere. Any other holds nothing and is out of its kind's reach, where
    it can't be wanted, so it stays as it is. Each gets its relevancy and
    band by its kind, a player and a body entering each at the inner radius
    and leaving past the outer, and one holding nothing out of range is done;
    the rest, in the order the states were walked, get whether anti-ESP
    hides them, which leaves them culled, and the stretch that follows.
    Invisible bodies are wanted by no one and never culled
--]]

local function consider(view: View, viewer: Viewer, own: number?)
	local clocked: boolean = Clock.on
	local origin: vector = viewer.position
	local distance: number = view.distance
	local grid: Grid = Radii.grid
	local bound: number = Constants.PLAY_BOUND

	-- f32 rounding moves an offset by under a millionth of its length, so the cells reach that much past each kind's
	-- reach, and no body found inside it lies outside them
	local slack: number = 2 ^ -20
	local covered: boolean = true

	for _, cells: Cells in grid.cells do
		-- A kind with no body this run keeps the empty reach the run gave it
		if cells.eastmost < 0 then
			continue
		end

		local size: number = cells.size
		local last: number = cells.across - 1
		local reach: number = math.min(cells.radius, distance) * (1 + slack)
		local west: number = (origin.x - reach + bound) // size
		local east: number = (origin.x + reach + bound) // size
		local south: number = (origin.z - reach + bound) // size
		local north: number = (origin.z + reach + bound) // size

		-- Held to the grid's edges as each body was, a NaN to its first cell
		west = west >= 0 and math.min(west, last) or 0
		east = east >= 0 and math.min(east, last) or 0
		south = south >= 0 and math.min(south, last) or 0
		north = north >= 0 and math.min(north, last) or 0

		local westmost: number, eastmost: number = cells.westmost, cells.eastmost
		local southmost: number, northmost: number = cells.southmost, cells.northmost
		if west > westmost or east < eastmost or south > southmost or north < northmost then
			covered = false
		end

		-- And to the cells holding the kind's bodies, which every body of it lies in, so a kind with none gathers none
		cells.west = math.max(west, westmost)
		cells.east = math.min(east, eastmost)
		cells.south = math.max(south, southmost)
		cells.north = math.min(north, northmost)
	end

	-- Cells that span every cell holding a body of each kind hold every body, which then go in the walk's own order
	local walkOrder: buffer = grid.walk
	local visits: { number } = grid.visits
	local count: number = grid.count

	if not covered then
		-- The cells' bodies, each as its place in the walk of the states times SLOTS plus its slot, in the walk's
		-- order within each cell
		local following: buffer = grid.following
		local orders: buffer = grid.orders
		count = 0

		for _, cells: Cells in grid.cells do
			local heads: buffer = cells.heads
			local across: number = cells.across

			for row: number = cells.south, cells.north do
				for column: number = cells.west, cells.east do
					local entry: number = buffer.readu16(heads, (row * across + column) * 2)
					while entry ~= 0 do
						local slot: number = entry - 1
						count += 1
						visits[count] = buffer.readu16(orders, slot * 2) * SLOTS + slot
						entry = buffer.readu16(following, slot * 2)
					end
				end
			end
		end

		-- And each slot it holds anything for outside its kind's cells, which lies outside its kind's reach. Most are
		-- players, whose cells are read once
		local players: Cells = grid.cells[PLAYER + 1]
		local west: number, east: number, south: number, north: number =
			players.west, players.east, players.south, players.north

		for _, slot: number in view.tracked do
			if buffer.readu32(Present, slot * 4) == Run then
				local column: number = buffer.readu16(grid.columns, slot * 2)
				local row: number = buffer.readu16(grid.rows, slot * 2)
				local kind: number = buffer.readu8(Kinds, slot)
				local inside: boolean

				if kind == PLAYER then
					inside = column >= west and column <= east and row >= south and row <= north
				else
					local cells: Cells = grid.cells[kind + 1]
					inside = column >= cells.west and column <= cells.east and row >= cells.south and row <= cells.north
				end

				if not inside then
					count += 1
					visits[count] = buffer.readu16(orders, slot * 2) * SLOTS + slot
				end
			end
		end
	end

	grid.visited += count

	if clocked then
		lapped(LAP.gather)
	end

	-- Out of range and holding nothing is all the rest would leave a pair, so only the others stay listed. SLOTS is a
	-- power of two, so a visit's slot is its low bits
	local viewFlags: buffer = view.flags
	local kinds: buffer = Kinds
	local positions: { vector } = grid.positions
	local slotBits: number = SLOTS - 1
	local listed: number = 0
	local ordered: boolean = true
	local enters: { number } = Tune.enters
	local leaves: { number } = Tune.leaves
	local outermost: number = Tune.bands - 1

	for index: number = 1, count do
		local slot: number
		local visit: number
		if covered then
			slot = buffer.readu16(walkOrder, index * 2)
			visit = index * SLOTS + slot
		else
			visit = visits[index]
			slot = bit32.band(visit, slotBits)
		end

		if slot == own then
			continue
		end

		local offset: vector = positions[slot + 1] - origin
		local squared: number = vector.dot(offset, offset)
		local kept: number = buffer.readu16(viewFlags, slot * 2)
		local kind: number = buffer.readu8(kinds, slot)
		local relevant: boolean
		local within: number = 0

		if kind == NPC then
			relevant = squared <= NpcRangeSquared
			if squared <= NpcNearSquared then
				within = 1
			end
		elseif kind == SLEEPER then
			relevant = squared <= SleeperSquared
		else
			if bit32.btest(kept, RELEVANT) then
				relevant = squared <= LeaveSquared
			else
				relevant = squared <= EnterSquared
			end

			-- The edges from the outermost in, up to the first it is outside: inside nearer than its enter, or still
			-- inside up to its leave when it was the run before
			local was: number = bit32.extract(kept, EDGES_AT, EDGES_WIDTH)
			for walked: number = 1, outermost do
				local edge: number = outermost - walked + 1
				if squared < enters[edge] or (walked <= was and squared <= leaves[edge]) then
					within = walked
				else
					break
				end
			end
		end

		-- Whether anti-ESP culls it is found afresh below
		local flags: number = bit32.band(kept, bit32.bnot(RELEVANT + EDGES + CULLED))
		if relevant then
			flags = bit32.replace(bit32.bor(flags, RELEVANT), within, EDGES_AT, EDGES_WIDTH)
		end

		if flags ~= 0 then
			if listed > 0 and visit < visits[listed] then
				ordered = false
			end

			listed += 1
			visits[listed] = visit
			buffer.writeu16(viewFlags, slot * 2, flags)
		elseif kept ~= 0 then
			buffer.writeu16(viewFlags, slot * 2, 0)
		end
	end

	-- The rest in the walk's order, the order anti-ESP is asked in and new slots join the tracked list in
	trim(visits, listed)
	if not ordered then
		table.sort(visits)
	end

	if clocked then
		lapped(LAP.measure)
	end

	local viewGenerations: buffer = view.generations
	local viewKinds: buffer = view.kinds
	local places: buffer = view.places
	local lookSent: buffer = view.lookSent
	local heldSent: buffer = view.heldSent
	local generations: buffer = Generations
	local invisible: buffer = Invisible
	local lookVersions: buffer = LookVersions
	local heldVersions: buffer = HeldVersions
	local lookLives: buffer = LookLives

	for index: number = 1, listed do
		local slot: number = bit32.band(visits[index], slotBits)
		local flags: number = buffer.readu16(viewFlags, slot * 2)
		local generation: number = buffer.readu8(generations, slot)
		local wanted: boolean = false
		if bit32.btest(flags, RELEVANT) and buffer.readu8(invisible, slot) ~= generation + 1 then
			if IsHidden(viewer, slot) then
				flags = bit32.bor(flags, CULLED)
			else
				wanted = true
			end
		end

		-- A new life ends whatever the viewer held of the slot's last one, and its reveal replaces any hide
		if bit32.btest(flags, SENT + REVEAL + HIDE) and buffer.readu8(viewGenerations, slot) ~= generation then
			flags = bit32.band(flags, bit32.bnot(STRETCH))
		end

		-- Settle's two steady stretches run here, one still sent with its look's changes as restyle finds them and
		-- one still not sent, and every other goes through settle
		if
			wanted
			and not bit32.btest(flags, HIDE)
			and bit32.btest(flags, SENT + REVEAL)
			and buffer.readu8(viewKinds, slot) == buffer.readu8(kinds, slot)
		then
			buffer.writeu8(viewGenerations, slot, generation)

			local version: number = buffer.readu16(lookVersions, slot * 2)
			if version ~= buffer.readu16(lookSent, slot * 2) then
				buffer.writeu16(lookSent, slot * 2, version)

				if buffer.readu8(lookLives, slot) == generation + 1 then
					flags = bit32.bor(bit32.band(flags, bit32.bnot(LOOK_CARRIED)), LOOK)
				end
			end

			version = buffer.readu16(heldVersions, slot * 2)
			if version ~= buffer.readu16(heldSent, slot * 2) then
				buffer.writeu16(heldSent, slot * 2, version)
				flags = bit32.bor(bit32.band(flags, bit32.bnot(HELD_CARRIED)), HELD)
			end
		elseif not wanted and not bit32.btest(flags, HIDE + SENT) then
			flags = bit32.band(flags, bit32.bnot(REVEAL + VISIBILITY_CARRIED + LOOKS))
		else
			flags = settle(view, slot, flags, wanted, generation)
		end

		if bit32.btest(flags, KEEP) and buffer.readu16(places, slot * 2) == 0 then
			track(view, slot)
		end

		buffer.writeu16(viewFlags, slot * 2, flags)
	end

	if clocked then
		lapped(LAP.settle)
	end
end

--[[
    Picks a viewer's crowd cap members once it has more candidates than
    tiers.crowd.size, the players it is sent this run with no reveal or hide
    pending: that many with the smallest key, ties to the lower slot, each
    the squared distance over the square of the pair's weight, a recent
    shooter's times the cone's unless its last run held it out of view.
    Gives whether the turn caps, its members stamped with the turn
--]]

local function cap(view: View, origin: vector): boolean
	local size: number = Tune.crowdSize
	local tracked: { number } = view.tracked
	local viewFlags: buffer = view.flags
	local count: number = 0

	for _, slot: number in tracked do
		if
			bit32.band(buffer.readu16(viewFlags, slot * 2), SENT + REVEAL + HIDE) == SENT
			and buffer.readu32(Present, slot * 4) == Run
			and buffer.readu8(Kinds, slot) == PLAYER
		then
			count += 1
		end
	end

	if count <= size then
		return false
	end

	local keys: buffer = Crowd.keys
	local slots: buffer = Crowd.slots
	local positions: { vector } = Radii.grid.positions
	local shotUntil: buffer = view.shotUntil
	local held: number = 0

	for _, slot: number in tracked do
		local flags: number = buffer.readu16(viewFlags, slot * 2)
		if
			bit32.band(flags, SENT + REVEAL + HIDE) ~= SENT
			or buffer.readu32(Present, slot * 4) ~= Run
			or buffer.readu8(Kinds, slot) ~= PLAYER
		then
			continue
		end

		local weight: number = 1
		if buffer.readu32(shotUntil, slot * 4) >= RunTick then
			weight = WeightShooter
		end

		if not bit32.btest(flags, OUTSIDE) then
			weight *= WeightCone
		end

		local offset: vector = positions[slot + 1] - origin
		local key: number = vector.dot(offset, offset) / (weight * weight)
		local place: number = held

		if held < size then
			-- Up from the end of the heap, past each parent nearer than it
			held += 1

			while place > 0 do
				local parent: number = (place - 1) // 2
				local parentKey: number = buffer.readf64(keys, parent * 8)
				local parentSlot: number = buffer.readu16(slots, parent * 2)
				if parentKey > key or (parentKey == key and parentSlot > slot) then
					break
				end

				buffer.writef64(keys, place * 8, parentKey)
				buffer.writeu16(slots, place * 2, parentSlot)
				place = parent
			end
		else
			-- Nearer than the farthest member, it takes that one's place and goes down past each child farther than it
			local rootKey: number = buffer.readf64(keys, 0)
			if key > rootKey or (key == rootKey and slot > buffer.readu16(slots, 0)) then
				continue
			end

			place = 0
			while place * 2 + 1 < size do
				local child: number = place * 2 + 1
				local childKey: number = buffer.readf64(keys, child * 8)
				local childSlot: number = buffer.readu16(slots, child * 2)
				local right: number = child + 1
				if right < size then
					local rightKey: number = buffer.readf64(keys, right * 8)
					local rightSlot: number = buffer.readu16(slots, right * 2)
					if rightKey > childKey or (rightKey == childKey and rightSlot > childSlot) then
						child, childKey, childSlot = right, rightKey, rightSlot
					end
				end

				if childKey < key or (childKey == key and childSlot < slot) then
					break
				end

				buffer.writef64(keys, place * 8, childKey)
				buffer.writeu16(slots, place * 2, childSlot)
				place = child
			end
		end

		buffer.writef64(keys, place * 8, key)
		buffer.writeu16(slots, place * 2, slot)
	end

	local turn: number = Crowd.turns + 1
	local members: buffer = Crowd.members
	Crowd.turns = turn
	Crowd.rest += count - size

	for place: number = 0, size - 1 do
		buffer.writef64(members, buffer.readu16(slots, place * 2) * 8, turn)
	end

	return true
end

--[[
    Lists what each slot the viewer holds anything for has pending, last
    tracked first: one no longer handed in ends, one holding nothing is let go,
    the rest list a hide, reveal or look entry, and a sent player's or NPC's
    record comes on its band's tick with a change or a repeat to send: owed
    once its floor is due, else queued by its weight times the relay ticks
    since its last, a player outside the crowd cap at the cap's rates and in
    a queue placed last. A player out of the cone past the out-of-view radius,
    no recent shooter, is held to that rate. Gives each list's count in order

    @ looking | the viewer's look, or with no out-of-view rate its body's
    facing, nil for a viewer with no body
    @ zoomed | whether its players go at the nearest band's aim and floor
    wherever they stand, their weights still their own band's

    @ missed | the relay ticks since the view's last turn when this turn
    follows a run it was left, whose credit each pair takes in full, held to
    MOST_CREDIT; 0 for any other turn, whose credit is one run's
--]]

local function schedule(
	view: View,
	own: number?,
	origin: vector,
	looking: vector?,
	zoomed: boolean,
	missed: number
): (number, number, number, number, number, number)
	local hides: number, reveals: number, restyles: number, floors: number, fills: number = 0, 0, 0, 0, 0
	local hideList: { number } = Lists.hides
	local revealList: { number } = Lists.reveals
	local restyleList: { number } = Lists.restyles
	local floorList: { number } = Lists.floors
	local fillList: { number } = Lists.fills
	local priorities: buffer = Lists.priorities
	local bands: number = Tune.bands
	local aims: { number } = Tune.aims
	local floorRates: { number } = Tune.floors
	local positions: { vector } = Radii.grid.positions
	local tracked: { number } = view.tracked
	local viewFlags: buffer = view.flags
	local shotUntil: buffer = view.shotUntil
	local aimCredits: buffer = view.aim
	local floorCredits: buffer = view.floor
	local lastRecord: buffer = view.lastRecord
	local repeats: buffer = view.repeats

	local cone: OutOfView? = OutOfViewRate
	local cosineSquared: number, radiusSquared: number, coneRate: number = 0, 0, 0
	local wide: boolean = false
	if cone then
		cosineSquared = cone.cosineSquared
		radiusSquared = cone.radiusSquared
		coneRate = cone.rate
		wide = cone.wide
	end

	-- Past the crowd cap's members, each player is held to the cap's rates and its fill queued after every other
	local capping: boolean = Tune.crowdSize > 0 and cap(view, origin)
	local members: buffer = Crowd.members
	local turn: number = Crowd.turns
	local crowdRate: number = Tune.crowdRate
	local crowdFloor: number = Tune.crowdFloor
	local restList: { number } = Lists.rest
	local rested: number = 0

	for index: number = #tracked, 1, -1 do
		local slot: number = tracked[index]
		local flags: number = buffer.readu16(viewFlags, slot * 2)
		local present: boolean = buffer.readu32(Present, slot * 4) == Run

		if not present and slot ~= own then
			-- A body no longer handed in is relevant to no one, and whatever the viewer was sent of it ends
			flags = bit32.band(flags, bit32.bnot(RELEVANT + EDGES + CULLED))
			flags = settle(view, slot, flags, false, buffer.readu8(view.generations, slot))
			buffer.writeu16(viewFlags, slot * 2, flags)
		end

		if not bit32.btest(flags, KEEP) then
			untrack(view, slot)
			continue
		end

		if bit32.btest(flags, HIDE) then
			hides += 1
			hideList[hides] = slot
		elseif not present then
			continue
		elseif bit32.btest(flags, REVEAL) then
			reveals += 1
			revealList[reveals] = slot
		elseif bit32.btest(flags, LOOK + HELD) and bit32.btest(flags, SENT + OWN) then
			restyles += 1
			restyleList[restyles] = slot
		end

		if not present or not bit32.btest(flags, SENT) or bit32.btest(flags, REVEAL + HIDE) then
			continue
		end

		local kind: number = buffer.readu8(Kinds, slot)
		if kind ~= PLAYER and kind ~= NPC then
			continue
		end

		local offset: vector = positions[slot + 1] - origin
		local within: number = bit32.extract(flags, EDGES_AT, EDGES_WIDTH)
		local aimRate: number
		local floorRate: number
		local weight: number = WeightFar
		local rest: boolean = false

		if kind == NPC then
			aimRate = NpcFarRate
			if within ~= 0 then
				aimRate = RelayRate
				weight = WeightNear
			end

			floorRate = aimRate
		else
			-- Its band's place from 1, the nearest inside every edge, whose rates a zoomed viewer is sent it at
			local band: number = bands - within
			if band == 1 then
				weight = WeightNear
			end

			if zoomed then
				band = 1
			end

			aimRate = aims[band]
			floorRate = floorRates[band]

			-- The cap's rates never raise a player's own
			if capping and buffer.readf64(members, slot * 8) ~= turn then
				rest = true
				aimRate = math.min(aimRate, crowdRate)
				floorRate = math.min(floorRate, crowdFloor)
			end
		end

		local shooter: boolean = buffer.readu32(shotUntil, slot * 4) >= RunTick
		if shooter then
			aimRate = math.max(aimRate, ShotRate)
			floorRate = math.max(floorRate, ShotRate)
			weight *= WeightShooter
		end

		-- The cone weighs where the out-of-view rate looks, and without one, the half space ahead of the body. The
		-- out-of-view cone around the look, a unit vector, is measured on the ground alone with no square root, so
		-- one straight above or below is inside
		local inside: boolean = false
		if looking then
			if cone then
				local along: number = offset.x * looking.x + offset.z * looking.z
				local reach: number = (offset.x * offset.x + offset.z * offset.z) * cosineSquared

				if wide then
					inside = along >= 0 or along * along <= reach
				else
					inside = along >= 0 and along * along >= reach
				end
			else
				inside = vector.dot(offset, looking) > 0
			end
		end

		if inside then
			weight *= WeightCone
		end

		local outside: boolean = false
		if cone and looking and not inside and kind == PLAYER and not shooter then
			outside = vector.dot(offset, offset) > radiusSquared
			if outside then
				aimRate = math.min(aimRate, coneRate)
				floorRate = math.min(floorRate, coneRate)
			end
		end

		-- Each band tick's credit for every relay tick since the last run, so its rate keeps its seconds, and after a
		-- run the viewer was left, for every relay tick since its last turn
		local aim: number
		local floor: number
		if missed > 0 then
			aim = math.min(buffer.readf32(aimCredits, slot * 4) + aimRate * missed / RelayRate, MOST_CREDIT)
			floor = math.min(buffer.readf32(floorCredits, slot * 4) + floorRate * missed / RelayRate, MOST_CREDIT)
		else
			aim = buffer.readf32(aimCredits, slot * 4) + math.min(aimRate * Elapsed / RelayRate, 1)
			floor = buffer.readf32(floorCredits, slot * 4) + math.min(floorRate * Elapsed / RelayRate, 1)
		end

		if outside then
			buffer.writeu16(viewFlags, slot * 2, bit32.bor(flags, OUTSIDE))
		elseif bit32.btest(flags, OUTSIDE) then
			-- Back from the out-of-view rate, so it is owed a record this run, in the hard room
			buffer.writeu16(viewFlags, slot * 2, bit32.band(flags, bit32.bnot(OUTSIDE)))
			aim = math.max(aim, 1)
			floor = math.max(floor, 1)
		end

		if aim < 1 then
			buffer.writef32(aimCredits, slot * 4, aim)
			buffer.writef32(floorCredits, slot * 4, floor)

			continue
		end

		local last: number = buffer.readu32(lastRecord, slot * 4)
		local still: boolean = buffer.readu32(Changed, slot * 4) <= last and buffer.readu8(repeats, slot) == 0

		-- Its band tick passes with nothing to send while it stays still
		if still and RunTick - last < StillTicks then
			buffer.writef32(aimCredits, slot * 4, aim - 1)
			buffer.writef32(floorCredits, slot * 4, math.max(floor - 1, 0))

			continue
		end

		buffer.writef32(aimCredits, slot * 4, aim)
		buffer.writef32(floorCredits, slot * 4, floor)
		buffer.writef64(priorities, slot * 8, weight * (RunTick - last))

		if floor >= 1 then
			floors += 1
			floorList[floors] = slot
		elseif rest then
			rested += 1
			restList[rested] = slot
		else
			fills += 1
			fillList[fills] = slot
		end
	end

	return hides, reveals, restyles, floors, fills, rested
end

-- Sends the open withheld block to the watchers alone
local function sendWithheld()
	if not WithheldOpen then
		return
	end

	WithheldOpen = false

	local data: buffer = exact(WithheldFilled)
	if Block.write(WithheldOut, data) ~= WithheldFilled then
		error("A withheld block wrote other than the bytes the relay counted for it")
	end

	SendWithheld(Watchers, data)

	-- The target whose turn it is, whose withheld records these are
	if Observing() then
		TapWithheld(Recipients[1], WithheldOut, data)
	end
end

-- Makes room for an entry of bytes in a withheld block section holding count, in a fresh block once it would pass
-- 896 B or its count
local function keep(bytes: number, count: number, sequence: number)
	if not WithheldOpen or WithheldFilled + bytes > BLOCK_BYTES or count >= SECTION_LIMIT then
		sendWithheld()

		WithheldOut.sequence = sequence
		WithheldOut.tick = TickWire
		WithheldOut.lookCount = 0
		WithheldOut.recordCount = 0
		WithheldOut.recordData = Records
		WithheldOpen = true
		WithheldFilled = HEADER_BYTES
	end

	WithheldFilled += bytes
end

--[[
    The watched target's withheld block: each culled player it is not sent,
    never an NPC or an Invisible or Parked one, nor a teammate, since
    anti-ESP never hides one. Each goes at its band's aim rate from the
    target every band tick, changed or not, with its look while pending,
    outside the target's budget and to the watchers alone. It carries the
    sequence of the run's last copy, so a look entry clears once the
    acknowledgments of that copy cover it
--]]

local function withhold(view: View)
	local withheld: Withheld? = view.withheld
	if not withheld then
		return
	end

	local records: number, looks: number = 0, 0
	local bands: number = Tune.bands
	local aims: { number } = Tune.aims

	for _, slot: number in view.tracked do
		local flags: number = buffer.readu16(view.flags, slot * 2)
		local mark: number = buffer.readu8(withheld.flags, slot)

		-- Only a body in this run's states that isn't Parked can be held back
		if
			buffer.readu32(Unparked, slot * 4) ~= Run
			or not bit32.btest(flags, CULLED)
			or bit32.btest(flags, SENT)
			or buffer.readu8(Kinds, slot) ~= PLAYER
		then
			if mark ~= 0 then
				buffer.writeu8(withheld.flags, slot, 0)
			end

			continue
		end

		local generation: number = buffer.readu8(Generations, slot)
		local aim: number

		if not bit32.btest(mark, WITHHELD) or buffer.readu8(withheld.lives, slot) ~= generation then
			-- It joins the withheld set, so its record goes now, with both parts of its look
			mark = WITHHELD + WITHHELD_HELD
			if dressed(slot) then
				mark += WITHHELD_LOOK
			end

			buffer.writeu8(withheld.lives, slot, generation)
			buffer.writeu16(withheld.lookSent, slot * 2, buffer.readu16(LookVersions, slot * 2))
			buffer.writeu16(withheld.heldSent, slot * 2, buffer.readu16(HeldVersions, slot * 2))
			aim = 1
		else
			if moved(withheld.lookSent, LookVersions, slot) and dressed(slot) then
				mark = bit32.bor(bit32.band(mark, bit32.bnot(WITHHELD_LOOK_CARRIED)), WITHHELD_LOOK)
			end

			if moved(withheld.heldSent, HeldVersions, slot) then
				mark = bit32.bor(bit32.band(mark, bit32.bnot(WITHHELD_HELD_CARRIED)), WITHHELD_HELD)
			end

			local rate: number = aims[bands - bit32.extract(flags, EDGES_AT, EDGES_WIDTH)]
			aim = buffer.readf32(withheld.aim, slot * 4) + math.min(rate * Elapsed / RelayRate, 1)
		end

		if aim >= 1 then
			aim -= 1
			records += 1
			WithheldRecords[records] = slot
		end

		buffer.writef32(withheld.aim, slot * 4, aim)
		buffer.writeu8(withheld.flags, slot, mark)

		if bit32.btest(mark, WITHHELD_LOOK + WITHHELD_HELD) then
			looks += 1
			WithheldLooks[looks] = slot
		end
	end

	if records + looks == 0 then
		return
	end

	-- A look entry rides beside a copy, whose acknowledgment clears it, so a run that has sent the target nothing
	-- sends it an empty block, inside its hard room
	if looks > 0 and not Copied and fits(view, 0, 0, Hard) then
		flush()
	end

	local logged: boolean = Copied
	local sequence: number = view.newest

	for index: number = 1, looks do
		local slot: number = WithheldLooks[index]
		local mark: number = buffer.readu8(withheld.flags, slot)
		local look: boolean = bit32.btest(mark, WITHHELD_LOOK)
		local held: boolean = bit32.btest(mark, WITHHELD_HELD)

		keep(entryBytes(slot, look, held), WithheldOut.lookCount, sequence)
		fillLook(WithheldOut, slot, look, held)

		if logged then
			if look then
				mark = carry(view, slot, WITHHELD_LOOK_PART, mark, WITHHELD_LOOK_CARRIED, withheld.lookFrom)
			end

			if held then
				mark = carry(view, slot, WITHHELD_HELD_PART, mark, WITHHELD_HELD_CARRIED, withheld.heldFrom)
			end

			buffer.writeu8(withheld.flags, slot, mark)
		end
	end

	for index: number = 1, records do
		keep(RECORD_BYTES, 0, sequence)

		local count: number = WithheldOut.recordCount + 1
		WithheldOut.records[count] = WithheldRecords[index] * RECORD_BYTES
		WithheldOut.recordCount = count
	end

	sendWithheld()
end

-- What the relay keeps for a viewer, made on its first run and kept until it is removed
local function viewOf(key: Key): View
	local kept: View? = Views[key]
	if kept then
		return kept
	end

	local made: View = {
		key = key,
		distance = Radii.leave,
		sequence = Constants.FIRST_SEQUENCE,
		newest = 0,
		turn = 0,
		turned = 0,
		own = nil :: number?,
		tracked = {} :: { number },
		places = buffer.create(SLOTS * 2),
		flags = buffer.create(SLOTS * 2),
		generations = buffer.create(SLOTS),
		kinds = buffer.create(SLOTS),
		visibilityFrom = buffer.create(SLOTS * 2),
		lookFrom = buffer.create(SLOTS * 2),
		heldFrom = buffer.create(SLOTS * 2),
		lookSent = buffer.create(SLOTS * 2),
		heldSent = buffer.create(SLOTS * 2),
		repeats = buffer.create(SLOTS),
		lastRecord = buffer.create(SLOTS * 4),
		shotUntil = buffer.create(SLOTS * 4),
		aim = buffer.create(SLOTS * 4),
		floor = buffer.create(SLOTS * 4),
		baseRuns = buffer.create(Deltas.on and SLOTS * 4 or 0),
		baseFloor = 0,
		ringSequences = buffer.create(RING * 4),
		ringRuns = buffer.create(RING * 4),
		ringStarts = buffer.create(RING * 8),
		ringCounts = buffer.create(RING * 2),
		ringOwed = buffer.create(RING * 4),
		log = buffer.create(LOG * 2),
		logHead = 0,
		watchers = {} :: { [number]: Key },
		bits = {} :: { [Key]: number },
		watcherRuns = buffer.create((MAX_WATCHERS + 1) * 4),
		watcherCount = 0,
		withheld = nil :: Withheld?,
	}
	Views[key] = made

	return made
end

local function newWithheld(): Withheld
	return {
		flags = buffer.create(SLOTS),
		lives = buffer.create(SLOTS),
		lookSent = buffer.create(SLOTS * 2),
		heldSent = buffer.create(SLOTS * 2),
		lookFrom = buffer.create(SLOTS * 2),
		heldFrom = buffer.create(SLOTS * 2),
		aim = buffer.create(SLOTS * 4),
	}
end

-- The view of a target that runs a turn of its own this run, which a watcher's copies come from, or nil
local function targetOf(target: Key): View?
	local view: View? = Views[target]
	if view and view.turn == Run then
		return view
	end

	return nil
end

--[[
    Gives a target's new watcher the target's lowest free bit, or nil past
    MAX_WATCHERS, and sends every withheld character's look again for it.
    Its client holds none of the target's records, so they go whole until
    it acknowledges a block from this run on
--]]

local function enlist(targetView: View, key: Key): number?
	for bit: number = 1, MAX_WATCHERS do
		if targetView.watchers[bit] == nil then
			targetView.watchers[bit] = key
			targetView.bits[key] = bit
			targetView.watcherCount += 1
			targetView.baseFloor = Run

			if targetView.watcherCount == 1 then
				table.insert(Watched, targetView)
			end

			local withheld: Withheld? = targetView.withheld
			if withheld then
				buffer.fill(withheld.flags, 0, 0)
			else
				targetView.withheld = newWithheld()
			end

			return bit
		end
	end

	return nil
end

--[[
    Takes a watcher no longer handed in watching its target off the
    target's blocks: each it was still to acknowledge is owed only by the
    rest, and one that none owes any more clears what it carried
--]]

local function unwatch(view: View, bit: number)
	local key: Key = view.watchers[bit]
	view.watchers[bit] = nil
	view.bits[key] = nil
	view.watcherCount -= 1

	local mask: number = 2 ^ bit
	for ring: number = 0, RING - 1 do
		local owed: number = buffer.readu32(view.ringOwed, ring * 4)
		if bit32.btest(owed, mask) then
			owed = bit32.band(owed, bit32.bnot(mask))
			buffer.writeu32(view.ringOwed, ring * 4, owed)

			if owed == 0 then
				discharge(view, ring)
			end
		end
	end
end

-- Unwatches every watcher of a watched view not handed in watching it this run, and a view left with none leaves
local function sweep(index: number)
	local view: View = Watched[index]

	for bit: number = 1, MAX_WATCHERS do
		if view.watchers[bit] ~= nil and buffer.readu32(view.watcherRuns, bit * 4) ~= Run then
			unwatch(view, bit)
		end
	end

	if view.watcherCount == 0 then
		Watched[index] = Watched[#Watched]
		Watched[#Watched] = nil
	end
end

-- The open block's recipients on a viewer's turn: the viewer, then each of its watchers by bit
local function address(view: View)
	Recipients[1] = view.key
	RecipientCount = 1
	RecipientMask = SELF

	local watchers: number = 0
	if view.watcherCount > 0 then
		for bit: number = 1, MAX_WATCHERS do
			local watcher: Key? = view.watchers[bit]
			if watcher ~= nil then
				RecipientCount += 1
				Recipients[RecipientCount] = watcher
				RecipientMask += 2 ^ bit
				watchers += 1
				Watchers[watchers] = watcher
			end
		end
	end

	trim(Recipients, RecipientCount)
	trim(Watchers, watchers)
end

--[[
    Readies the run's views: every viewer's, made on its first run, marked
    for a turn of its own when it has no target, each watcher its target
    already counts seen again, and every watcher no longer handed in
    watching its target taken off it
--]]

function Turn.ready(viewers: { Viewer })
	for _, viewer: Viewer in viewers do
		local view: View = viewOf(viewer.key)
		if viewer.target == nil then
			view.turn = Run
		end
	end

	-- Each watcher its target already counts is seen again, so only those that left stop being required
	for _, viewer: Viewer in viewers do
		local target: Key? = viewer.target
		if target ~= nil then
			local targetView: View? = targetOf(target)
			if targetView then
				local bit: number? = targetView.bits[viewer.key]
				if bit ~= nil then
					buffer.writeu32(targetView.watcherRuns, bit * 4, Run)
				end
			end
		end
	end

	for index: number = #Watched, 1, -1 do
		sweep(index)
	end
end

--[[
    A watcher's run: it is one of its target's recipients, the target's
    blocks numbered past latest, the newest block its client was sent
    elsewhere, when it starts watching, 0 otherwise, and its acknowledgment
    counts for the target's blocks it was sent. Nil when the target runs no
    turn of its own this run, false when it already has all the watchers it
    takes, and true once the watcher is one of its recipients
--]]

function Turn.watch(viewer: Viewer, target: Key, latest: number): boolean?
	local targetView: View? = targetOf(target)
	if not targetView then
		return nil
	end

	local key: Key = viewer.key
	local held: number? = targetView.bits[key]
	local bit: number

	if held then
		bit = held
	else
		local given: number? = enlist(targetView, key)
		if given == nil then
			return false
		end

		bit = given
	end

	renumber(targetView, latest)
	buffer.writeu32(targetView.watcherRuns, bit * 4, Run)
	acknowledge(targetView, viewer.acknowledged, viewer.received, 2 ^ bit)

	return true
end

--[[
    One viewer's turn: its acknowledgment, its own character, every body
    against it, then its blocks, each copied to its watchers: pending hides,
    reveals and looks, the footsteps it can hear, the records it is owed
    inside the hard budget and the rest inside the soft budget, and last
    the withheld block, to its watchers alone, each part timed into
    Turn.clocks while relay.clocks is on

    @ back | the newest block its client was sent watching, on the run it
    is back from a spectate, nil on any other

    @ missed | whether the relay's budget left the viewer in the run
    before, so each pair's credit counts every relay tick since its last
    turn, held to MOST_CREDIT, and it hears that run's footsteps first
--]]

function Turn.turn(viewer: Viewer, back: number?, missed: boolean?)
	local clocked: boolean = Clock.on
	if clocked then
		Clock.from = os.clock()
	end

	local key: Key = viewer.key
	local view: View = viewOf(key)
	local since: number = 0
	if missed and view.turned ~= 0 then
		since = RunTick - view.turned
	end

	view.turned = RunTick

	-- Its own radii: players and bodies enter inside its distance in the server's proportion and leave past it, and
	-- sleepers and NPCs go no farther than it either
	local distance: number = view.distance
	EnterSquared = (distance * Radii.enter / Radii.leave) ^ 2
	LeaveSquared = distance * distance
	SleeperSquared = math.min(Radii.sleepers, distance) ^ 2
	NpcRangeSquared = math.min(Radii.npcs, distance) ^ 2

	-- Back from a spectate, its client may acknowledge the target's blocks a while yet, so its own go on past them,
	-- and its records go whole until it acknowledges one of them
	if back ~= nil then
		renumber(view, back)
		view.baseFloor = Run
	end

	acknowledge(view, viewer.acknowledged, viewer.received, SELF)
	address(view)
	Copied = false

	local own: number? = viewer.slot
	if own ~= nil and not Valid(own) then
		error(`A viewer's slot is one of the slot table's slots, not {own}`)
	end

	claim(view, own)

	if clocked then
		lapped(LAP.head)
	end

	consider(view, viewer, own)

	-- Where the view cone looks while the viewer has a body: its newest look with the out-of-view rate, until its
	-- first one its body's facing, and without the rate always its facing
	local origin: vector = viewer.position
	local looking: vector? = nil
	if own ~= nil and buffer.readu32(Present, own * 4) == Run then
		local look: vector? = viewer.look
		if OutOfViewRate and look then
			looking = look
		else
			local facing: number = buffer.readf64(Facings, own * 8)
			looking = vector.create(-Math.sin(facing), 0, -Math.cos(facing))
		end
	end

	local hides: number, reveals: number, restyles: number, floors: number, fills: number, rested: number =
		schedule(view, own, origin, looking, viewer.zoomed == true, since)

	if clocked then
		lapped(LAP.schedule)
	end

	-- Its traffic is read the first time it needs room, so a viewer with nothing due makes no read
	Used = nil
	Spent = 0

	for index: number = 1, hides do
		addHide(view, Lists.hides[index])
	end

	for index: number = 1, reveals do
		addReveal(view, Lists.reveals[index])
	end

	for index: number = 1, restyles do
		addLook(view, Lists.restyles[index])
	end

	-- A culled enemy's steps go once, to each viewer it is culled from inside the step's range, and a turn after a
	-- run its viewer was left hears the steps of that run first, a run late, as it finds the enemies this turn
	if missed then
		listen(view, origin, Steps.count, Steps.count + Steps.carried - 1)
	end

	listen(view, origin, 0, Steps.count - 1)

	placeRecords(view, Lists.floors, floors, Hard)
	placeRecords(view, Lists.fills, fills, Soft)

	-- The fills of the players outside the crowd cap take only the soft room the others leave
	if rested > 0 then
		placeRecords(view, Lists.rest, rested, Soft)
	end

	if clocked then
		lapped(LAP.place)
	end

	flush()

	if view.watcherCount > 0 then
		withhold(view)
	end

	if clocked then
		lapped(LAP.send)
	end
end

--[[
    A shooter's bullet passed near a viewer, so the shooter's record goes
    to it at no less than shotNear.rate through the relay tick given, while
    the viewer is sent the shooter
--]]

function Turn.shotNear(key: Key, slot: number, through: number)
	local view: View? = Views[key]
	if view then
		buffer.writeu32(view.shotUntil, slot * 4, through)
	end
end

-- Gives a viewer a fresh pending reveal of a slot it is sent, with its record and its look in the same block
function Turn.reveal(key: Key, slot: number)
	local view: View? = Views[key]
	if view then
		buffer.writeu16(view.flags, slot * 2, revealAgain(view, slot, buffer.readu16(view.flags, slot * 2)))
	end
end

--[[
    Makes every character a viewer is currently sent a pending reveal again,
    with its look and held item in the same block, and its own character's
    look entry too, its records going whole until a block from the run
    floor on is acknowledged
--]]

function Turn.revealAll(key: Key, floor: number)
	local view: View? = Views[key]
	if not view then
		return
	end

	view.baseFloor = floor

	for _, slot: number in view.tracked do
		local flags: number = buffer.readu16(view.flags, slot * 2)

		if bit32.btest(flags, SENT) then
			buffer.writeu16(view.flags, slot * 2, revealAgain(view, slot, flags))
		elseif bit32.btest(flags, OWN) then
			buffer.writeu16(view.flags, slot * 2, lookAgain(view, slot, flags))
		end
	end
end

-- Keeps a viewer's render distance in studs, held to relevancy.leave, from its next turn on
function Turn.setDistance(key: Key, distance: number)
	viewOf(key).distance = math.min(distance, Radii.leave)
end

-- Forgets a viewer, with everything pending for it
function Turn.remove(key: Key)
	Views[key] = nil
end

-- The view kept for a key, or nil before its first run
function Turn.view(key: Key): View?
	return Views[key]
end

-- Every view, by its key
function Turn.views(): { [Key]: View }
	return Views
end

--[[
    The running totals since start of the records the band ticks placed in
    a viewer's blocks, of those the viewer's room left out, of the bodies
    the viewers' turns gathered to measure, and of the candidates the turns
    held outside their viewer's crowd cap
--]]

function Turn.counts(): (number, number, number, number)
	return RecordsSent, RecordsCut, Radii.grid.visited, Crowd.rest
end

--[[
    With relay.clocks on, the seconds each part of this run's turns took so
    far, summed over them, an f64 a part: head, gather, measure, settle,
    schedule, place and send, as Wire.CLOCKS names them first. The buffer is
    the core's own, rewritten by each turn and zeroed by each begin
--]]

function Turn.clocks(): buffer
	return Clock.laps
end

return Turn
