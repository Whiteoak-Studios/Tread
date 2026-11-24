--[[
    The relay: each run's walk of the live states into the world a viewer's
    turn reads, every watch and turn in viewer order, in Turn or on the Actor
    workers relay.workers makes, and the members the server handle calls
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Codec.Block)
local Config = require(script.Parent.Parent.Config)
local Constants = require(script.Parent.Parent.Constants)
local Command = require(script.Parent.Parent.Codec.Command)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Keyframe = require(script.Parent.Parent.Codec.Keyframe)
local Math = require(script.Parent.Parent.Step.Math)
local Pool = require(script.Parent.RelayWorkers.Pool)
local Record = require(script.Parent.Parent.Codec.Record)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.Parent.Codec.StateWord)
local Taps = require(script.Parent.Taps)
local Turn = require(script.Turn)
local Wire = require(script.Wire)

local SLOTS: number = Constants.SLOTS
local RECORD_BYTES: number = Constants.RECORD_BYTES
local FOOTSTEP_BYTES: number = Constants.FOOTSTEP_BYTES
local MAX_LOOK: number = Constants.MAX_LOOK
local MAX_HELD: number = Constants.MAX_HELD
local MAX_WATCHERS: number = Constants.MAX_WATCHERS
local DEPTH: number = Constants.CHANGE_DEPTH -- Relay runs of records the history keeps, a plane a run
local COUNTERS: number = 2 ^ Constants.COUNTER_BITS -- The values a state word's jump or land counter wraps through
local WRAP: number = 2 ^ 16 -- The values a u16 wire number wraps through
local BYTES_PER_KB: number = 1000 -- A budget's KB, as the design counts them
local TURN: number = 360 -- Degrees
local QUARTER_TURN: number = TURN / 4 -- The degrees a record's pitch steps reach either way
local ROW_BYTES: number = Wire.ROW_BYTES -- A viewer's row of anti-ESP's answers
local NO_TEAM: number = 0 / 0 -- A hand's team for a viewer with no slot, which equals no team
local WORKERS_FOLDER: string = "TreadRelayWorkers" -- The folder under ServerScriptService the workers are cloned into
local WINDOW_SECONDS: number = 10 -- How far back each clock's runs are kept, the span stats reads its p95 over
-- relay.budget leaves a viewer at most one run in this many, and in a run at most one in this many of a mode's turn
-- viewers, rounded down
local LEFT_EVERY: number = 4

local TURN_CHANGE: number = 0.5 -- Degrees a yaw or pitch moves by before the move alone counts as a change
local YAW_CHANGE: number = Constants.ANGLE_STEPS * TURN_CHANGE / TURN -- That move in a record's yaw steps
local PITCH_CHANGE: number = Constants.RECORD_PITCH_STEPS * TURN_CHANGE / QUARTER_TURN -- And in its pitch steps

local SILENT: number = -1 -- A squared range no step falls inside, for a kind the game gives no range

-- The code the world keeps for each kind, its place in Block's list from 0, and the flags a view's queries read
local KIND_CODES: { [string]: number } = Turn.KIND_CODES
local PLAYER: number = KIND_CODES.Player
local NPC: number = KIND_CODES.Npc
local SENT: number = Turn.SENT
local OWN: number = Turn.OWN
local WITHHELD: number = Turn.WITHHELD

-- A footstep's kinds by code from 1, each heard to the range keyed by its name in lower case
local STEPS: { Block.Step } = { "Walk", "Sprint", "Jump", "Land" }
local WALK: number = 1
local SPRINT: number = 2
local JUMP: number = 3
local LAND: number = 4

-- The sections the relay's clocks time past a worker's own: the slowest worker's run and fire, the main thread's at the
-- dispatch and at the finish, its waits, and last the two measured across a worker's clock and the main thread's
local FRONT_CLOCKS: { string } = {
	"run",
	"fire",
	"walk",
	"file",
	"inProcess",
	"answers",
	"shared",
	"own",
	"handIn",
	"flushTick",
	"open",
	"land",
	"asks",
	"sends",
	"deferred",
	"flushFinish",
	"round",
	"waitBeat",
	"delivery",
	"back",
}

-- Every section, an f64 each in this order: a worker's as Wire.CLOCKS lays them out, summed over the workers so the
-- run's turns' parts lead, then the rest
local CLOCKS: { string } = table.move(FRONT_CLOCKS, 1, #FRONT_CLOCKS, #Wire.CLOCKS + 1, table.clone(Wire.CLOCKS))

local CLOCK_AT: { [string]: number } = {} -- Each section's offset in a run's clocks
for index: number, name: string in CLOCKS do
	CLOCK_AT[name] = (index - 1) * 8
end

type Band = Config.Band
type Command = State.Command
type Copy = Wire.Copy
type Crowd = Config.Crowd
type Edge = Config.Edge
type Hand = Wire.Hand
type Layout = Fields.Layout
type Limits = Command.Limits
type OutOfView = Turn.OutOfView
type Pool = Pool.Pool
type Reader = Wire.Reader
type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type State = State.State
type Steps = Turn.Steps
type UnderLoad = Config.UnderLoad
type Values = State.Values
type View = Turn.View
type Withheld = Turn.Withheld
type World = Turn.World

type Bot = { Name: string }
type Key = Player | Bot
type Platforms = { [number]: vector } -- Each platform's place at the tick, by its id

-- What the server handle starts the relay with: the game's checked tables, its compiled declarations, and the clock
-- the frame caps read, os.clock when left out
export type Settings = {
	shared: Shared,
	server: ServerSettings,
	layout: Layout,
	clock: (() -> number)?,
}

-- One viewer as the server handle hands it in each relay tick, a table it keeps and refills
export type Viewer = {
	key: Key, -- The player or bot, which the relay keeps its view under and hands send and traffic
	slot: number?, -- Its own character's slot, nil while it has none
	position: vector, -- Where its relevancy, bands and earshot are measured from
	acknowledged: number, -- The newest relay sequence its client received, 0 for none
	received: number, -- The mask of the 16 sequences before that one, bit 0 the one just before
	target: Key?, -- The viewer it spectates, whose blocks it gets copies of in place of its own; nil for none
	look: vector?, -- The newest look its client sent, a unit vector on the ground; nil before any
	zoomed: boolean?, -- Whether its players go at the nearest band's rates wherever they stand; nil as false
}

-- Anti-ESP's port that takes a viewer the relay's budget left, with the slots its view tracks and their count
type Passed = (viewer: Viewer, slots: { number }, count: number) -> ()

-- One section of the relay's clocks over its last WINDOW_SECONDS of runs, a run's seconds each, which stats reads
export type ClockRing = {
	times: { number }, -- Made at its full size
	held: number, -- The runs it holds, up to its size, the first that many of times
	head: number, -- The index the next run goes at
	last: number, -- The newest run's, 0 before the first
}

-- Anti-ESP's answers for a run's viewers, as AntiEsp.answers lays them out: each slot's kind and team, and two rows of
-- bits a viewer by its place in the list, visible and quiet
type Answers = {
	kinds: buffer,
	teams: buffer,
	visible: buffer,
	quiet: buffer,
}

-- What the queries read of a view: the in-process Turn's own, or the front's copy of one a worker hosts
type Seen = {
	read own: number?,
	read tracked: { number },
	read flags: buffer,
	read generations: buffer,
	read kinds: buffer,
	read withheld: { read flags: buffer, read lives: buffer }?,
}

-- What a keyframe reads that each run's walk writes: the world's own, or, while a round is out, as the run before
-- left it, which the copies are as of
type Facts = {
	tick: number, -- The relay tick the run's blocks carry, a u16
	records: buffer,
	helds: buffer,
	heldLengths: buffer,
	generations: buffer,
}

-- One Actor worker as the front keeps it between runs
type Worker = {
	views: number, -- The views made on it, which a new view's home is picked by
	list: { Viewer }, -- This run's viewers handed to it, in the run's order
	places: { number }, -- Each one's place from 1 in the run's viewers
	count: number,
	watchers: number, -- How many of them watch a target
	hands: { Hand }, -- Each one as its own hand-in carries it, the tables kept run to run
	own: buffer, -- This run's own hand-in, written before any worker is sent its round
	calls: Wire.Calls, -- The calls queued for its views since its last hand-in
	reader: Reader,
	round: number, -- The round it was sent this run, 0 for none
	failure: string?, -- What its run threw, once that round landed with no result
	resend: boolean, -- Whether its next hand-in has it send each view it runs whole
	sent: number, -- The last run it was sent, 0 for none
}

local Started: boolean = false
local Layout: Layout = Fields.compile({ command = {}, rules = {}, server = {}, slot = {}, held = {} })
local Limits: Limits = { lean = 0, headCone = 0 }

-- What the keyframes take from start: the declarations' hash, and the shared table's gravity, which a keyframe given
-- none carries
local Keyed: { hash: number, gravity: number } = { hash = 0, gravity = 0 }

-- The game's settings the front reads itself: whether records go as changes, the relay ticks a shot near a viewer
-- raises its shooter's rate for, the strides steps fall at, and each footstep kind's squared range, which every turn
-- reads too
local Changes: boolean = false
local ShotTicks: number = 0
local StrideWalk: number = 0
local StrideSprint: number = 0
local Earshot: { number } = { SILENT, SILENT, SILENT, SILENT }

local Run: number = 0 -- The relay runs so far, which every timing but those in seconds counts in
local RunTick: number = 0 -- The relay tick of this run, or the last, unwrapped, which the timings in seconds count in
local Elapsed: number = 1 -- The relay ticks since the run before, more than 1 after runs a catch-up skipped
local TickWire: number = 0 -- The relay tick this run's blocks carry, a u16

-- The world every turn reads, which the front fills each run from the states and between runs from the members
local World: World = Turn.world
local Present: buffer = World.present
local Generations: buffer = World.generations
local Kinds: buffer = World.kinds
local Unparked: buffer = World.unparked
local Facings: buffer = World.facings
local Positions: { vector } = World.positions
local Walk: buffer = World.walk
local Records: buffer = World.records
local Changed: buffer = World.changed
local Looks: buffer = World.looks
local LookLengths: buffer = World.lookLengths
local LookVersions: buffer = World.lookVersions
local LookLives: buffer = World.lookLives
local Helds: buffer = World.helds
local HeldLengths: buffer = World.heldLengths
local HeldVersions: buffer = World.heldVersions
local Invisible: buffer = World.invisible
local Steps: Steps = World.steps

local References: buffer = buffer.create(SLOTS * RECORD_BYTES) -- The record each change is measured from

-- Each slot's last sample for its footsteps: where it stood, and what its steps since its last step have covered, in
-- one table since Luau caps a chunk's locals
local Samples: {
	positions: { vector },
	materials: { Enum.Material }, -- The ground it last stood on
	runs: buffer, -- u32: the run it was sampled at, 0 for never
	lives: buffer, -- u8
	epochs: buffer, -- u8
	jumps: buffer, -- u8
	lands: buffer, -- u8
	stepping: buffer, -- u8: 1 when it stood in a gait that steps
	walked: buffer, -- f64: studs since its last step
} =
	{
		positions = table.create(SLOTS, vector.zero),
		materials = table.create(SLOTS, Enum.Material.Air),
		runs = buffer.create(SLOTS * 4),
		lives = buffer.create(SLOTS),
		epochs = buffer.create(SLOTS),
		jumps = buffer.create(SLOTS),
		lands = buffer.create(SLOTS),
		stepping = buffer.create(SLOTS),
		walked = buffer.create(SLOTS * 8),
	}

local Scratch: Record.Record = Record.new()
local Footstep: Block.Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
local LookScratch: buffer = buffer.create(MAX_LOOK)
local HeldScratch: buffer = buffer.create(MAX_HELD)

-- What each viewer's client was sent and whom it watches, by key, which a watch and a return from one read across
-- views, so they are kept here and handed to the turns that need them
local Heard: { [Key]: number } = {} -- The sequence of the newest block its client was sent, its own or a copy
local Watching: { [Key]: Key } = {} -- The target it last watched, nil while its own view runs

-- The ports start hands in, which the front calls itself for the turns its workers took
local Send: (keys: { Key }, data: buffer) -> ()
local SendWithheld: (keys: { Key }, data: buffer) -> ()
local Traffic: (key: Key) -> number
local IsHidden: (viewer: Viewer, slot: number) -> boolean
local AnswersOf: (viewers: { Viewer }) -> Answers
local Asked: (viewer: Viewer, slots: { number }, count: number) -> ()

-- The workers while relay.workers is above 0, nil otherwise, each kept as a Worker, and whether new views go to them
local Workers: Pool? = nil
local Hosts: { Worker } = {}
local UseWorkers: boolean = false

-- Each key's id from the first hand-in that names it, never given to another key, and the key each id names. A key
-- removed keeps its id until the next hand-in, so one handed in again by then keeps the watcher bits its targets'
-- views hold for it, as Turn keeps them by key until its next sweep
local Ids: { [Key]: number } = {}
local Keys: { [number]: Key } = {}
local NextId: number = 0
local Leaving: { [Key]: boolean } = {}

-- Each view's home, 0 for the in-process Turn or the index of the worker it was made on, set where Turn makes a view
-- and dropped where Turn drops one. Walking it keeps no order: a key that leaves and comes back can land elsewhere in
-- the table after a collection, so neither its walk nor Turn's views' is a contract
local Homes: { [Key]: number } = {}
local Copies: { [Key]: Copy } = {} -- The front's copy of each view a worker hosts, as its last result left it
local Revealed: { [Key]: { [number]: number } } = {} -- The kinds a reveal gave a copy's slots since its worker ran it
local Stale: { [Key]: boolean } = {} -- The copies whose worker sends its view whole the next time it runs it

-- The rounds sent since start, whether this run's is out, the viewers it went out for, and the first target with
-- more watchers than it takes, with that watcher's place in the list
local Round: number = 0
local Out: boolean = false
local RunViewers: { Viewer } = {}
local Overfull: Key? = nil
local OverfullAt: number = 0

-- For each viewer by its place in the run's list, kept run to run: its home, its place in its worker's list, its
-- target as the run was sent, false for none, that target's home, 0 for the in-process Turn or none, its place among
-- that worker's watchers, whether its watch starts there, and whether it is back from a spectate on its worker
local Dispatch: {
	homes: { number },
	places: { number },
	watched: { Key | false },
	targets: { number },
	ordinals: { number },
	starting: { boolean },
	returning: { boolean },
} =
	{ homes = {}, places = {}, watched = {}, targets = {}, ordinals = {}, starting = {}, returning = {} }

local InProcess: { Viewer } = {} -- This run's viewers the in-process Turn takes, in the run's order

-- The distance bands and their edges as tiers or Relay.setBands last gave them, and the crowd cap as tiers or
-- Relay.setCrowd did, nil for none, each copied, and as every turn reads them
local Bands: { given: { Band }, edges: { Edge }, crowd: Crowd?, tuning: Turn.Tuning } =
	{ given = {}, edges = {}, crowd = nil, tuning = Wire.tuning() }

-- The shared hand-in's facts beside the world: the run's bands, the looks and Invisible marks set since the last
-- hand-in, the held items this run's walk changed, the keys a sink observes, and anti-ESP's kinds and teams, filled at
-- dispatch
local Header: Wire.Shared = {
	run = 0,
	tick = 0,
	elapsed = 0,
	wire = 0,
	tune = Bands.tuning,
	places = 0,
	looks = {},
	lookCount = 0,
	helds = {},
	heldCount = 0,
	observing = false,
	observed = {},
	observedCount = 0,
	kinds = buffer.create(0),
	teams = buffer.create(0),
}
local Marked: buffer = buffer.create(SLOTS) -- u8: 1 for a slot in the header's looks

-- The calls made while a round is out, in call order, each with what it worked out at the call
local Deferred: {
	kinds: { number },
	keys: { [number]: Key },
	slots: { number },
	values: { number },
	count: number,
} =
	{ kinds = {}, keys = {}, slots = {}, values = {}, count = 0 }

-- The world's facts a keyframe reads, and the same as the last run left them, made at start with workers
local Live: Facts = { tick = 0, records = Records, helds = Helds, heldLengths = HeldLengths, generations = Generations }
local Frozen: Facts = {
	tick = 0,
	records = buffer.create(0),
	helds = buffer.create(0),
	heldLengths = buffer.create(0),
	generations = buffer.create(0),
}

-- The workers' running totals of the records placed and cut, the bodies gathered and the candidates held outside a
-- crowd cap, summed from their results
local Totals: { sent: number, cut: number, visited: number, rest: number } =
	{ sent = 0, cut = 0, visited = 0, rest = 0 }

-- The frame caps the relay keeps, each set by its seam and nil while off, with the clock they read and anti-ESP's
-- port for a viewer left, the seams' calls so far, and what the run being taken left and measured under the budget it
-- began with. Each key keeps the run it was last left and whether its next turn follows one it missed, and the run
-- keeps its watched targets, the turn viewers in the order the budget takes them, where the next run's rest begin, the
-- worker turns the next run hands in, nil for all, the runs over and under the budget in a row, and the running totals
local Caps: {
	clock: () -> number,
	passed: Passed?,
	budget: number?,
	underLoad: UnderLoad?,
	sets: number, -- The calls of Relay.setBudget and Relay.setUnderLoad since start
	running: number?, -- The budget the run being taken began under, which its finish reads
	ranAfter: number, -- And the seams' calls before it, so a finish after another call neither measures nor judges
	began: number,
	measured: number, -- Its seconds so far, Relay.run's own and then its finish's
	left: number, -- Its viewers left
	handed: number, -- Its worker turns handed in
	first: number, -- How far past the cursor the first viewer it left stands in its list, math.huge for none
	lefts: { [Key]: number }, -- So its turn the run after follows one it missed
	away: { [Key]: boolean }, -- Its worker viewers left
	guarded: { [Key]: boolean },
	order: { number }, -- Places from 1 in its list
	free: { boolean }, -- By place in order: whether the budget may leave that viewer
	cursor: number,
	hand: number?,
	overs: number,
	unders: number,
	lowered: boolean,
	totalLeft: number,
	totalOver: number,
	halved: number, -- The runs taken with the farthest band lowered
} =
	{
		clock = os.clock,
		passed = nil,
		budget = nil,
		underLoad = nil,
		sets = 0,
		running = nil,
		ranAfter = 0,
		began = 0,
		measured = 0,
		left = 0,
		handed = 0,
		first = math.huge,
		lefts = {},
		away = {},
		guarded = {},
		order = {},
		free = {},
		cursor = 1,
		hand = nil,
		overs = 0,
		unders = 0,
		lowered = false,
		totalLeft = 0,
		totalOver = 0,
		halved = 0,
	}

-- With relay.clocks on: the running run's seconds in each section at its offset in CLOCK_AT, each section's ring, the
-- runs a ring holds, whether the laps hold a run the rings don't yet, when the lap being timed began, when the
-- dispatch ended, the newest result's landing, and how many workers' clocks the finish took in
local Clock: {
	on: boolean,
	laps: buffer,
	rings: { [string]: ClockRing },
	capacity: number,
	pending: boolean,
	from: number,
	dispatched: number,
	landed: number,
	workers: number,
} =
	{
		on = false,
		laps = buffer.create(#CLOCKS * 8),
		rings = {},
		capacity = 0,
		pending = false,
		from = 0,
		dispatched = 0,
		landed = 0,
		workers = 0,
	}

-- A worker turn's recipients as keys, then its watchers alone, its asks' and then its marks' walk places, the marks
-- turned into slots in place, and a list of one key
local Recipients: { Key } = {}
local Watchers: { Key } = {}
local Places: { number } = {}
local One: { Key } = {}

-- The sections the relay's clocks time, in their order, which a dev run's lines print them in
local Relay = {
	CLOCKS = CLOCKS,
}

-- The squared range a footstep kind is heard to, or SILENT for a kind the game gives none
local function earshot(range: number?): number
	if range == nil then
		return SILENT
	end

	return range * range
end

-- Each of the first count keys' clients was sent the block of a sequence
local function hear(keys: { Key }, count: number, sequence: number)
	for index: number = 1, count do
		Heard[keys[index]] = sequence
	end
end

-- The ports that reach the taps, each reading its member of Taps at the call and never at start, so nothing of Taps
-- past its flag is reached while no sink observes
local function observing(): boolean
	return Taps.observing
end

local function observes(keys: { Key }, count: number): boolean
	return Taps.observes(keys, count)
end

local function relayed(keys: { Key }, count: number, block: Block.Block, data: buffer)
	Taps.relayed(keys, count, block, data)
end

local function tapWithheld(target: Key, block: Block.Block, data: buffer)
	Taps.withheld(target, block, data)
end

-- Cuts a kept list back to its first count entries
local function trim<T>(list: { T }, count: number)
	for index: number = #list, count + 1, -1 do
		list[index] = nil
	end
end

--[[
    Keeps distance bands and their edges, each copied, and works them out
    in place into the bands every turn reads: each band's aim and floor, and
    each edge's radii squared, the crowd cap's fields left as they are
--]]

local function tune(bands: { Band }, edges: { Edge })
	local tuning: Turn.Tuning = Bands.tuning
	local count: number = #bands
	tuning.bands = count

	for index: number, band: Band in bands do
		Bands.given[index] = { aim = band.aim, floor = band.floor }
		tuning.aims[index] = band.aim
		tuning.floors[index] = band.floor
	end

	for index: number, edge: Edge in edges do
		Bands.edges[index] = { enter = edge.enter, leave = edge.leave }
		tuning.enters[index] = edge.enter ^ 2
		tuning.leaves[index] = edge.leave ^ 2
	end

	trim(Bands.given, count)
	trim(tuning.aims, count)
	trim(tuning.floors, count)
	trim(Bands.edges, #edges)
	trim(tuning.enters, #edges)
	trim(tuning.leaves, #edges)
end

-- Puts the farthest band's aim and floor in the bands every turn reads as given, or times tiers.underLoad.scale while
-- the far rate under load holds it lowered. With one band there is none farther to lower
local function lowerFar()
	local tuning: Turn.Tuning = Bands.tuning
	local count: number = tuning.bands
	if count < 2 then
		return
	end

	local scale: number = 1
	local underLoad: UnderLoad? = Caps.underLoad
	if Caps.lowered and underLoad then
		scale = underLoad.scale
	end

	local band: Band = Bands.given[count]
	tuning.aims[count] = band.aim * scale
	tuning.floors[count] = band.floor * scale
end

-- Keeps a crowd cap, copied, or none, and puts it in the bands every turn reads, its size 0 for none
local function tuneCrowd(crowd: Crowd?)
	local tuning: Turn.Tuning = Bands.tuning

	if crowd then
		Bands.crowd = { size = crowd.size, rate = crowd.rate, floor = crowd.floor }
		tuning.crowdSize = crowd.size
		tuning.crowdRate = crowd.rate
		tuning.crowdFloor = crowd.floor
	else
		Bands.crowd = nil
		tuning.crowdSize = 0
		tuning.crowdRate = 0
		tuning.crowdFloor = 0
	end
end

--[[
    Starts the relay with the game's tables and what it sends through: send
    fires one block to a viewer and the moderators watching it, and
    sendWithheld one withheld block to those moderators, each in one
    fireList over the relay's own list, valid during the call; traffic is
    Volt's count of the bytes sent to a viewer over the last second,
    isHidden is anti-ESP's answer for a pair, answers anti-ESP's export of
    them, and asked takes a viewer's asks whose quiet bit was set in their
    place, both of which relay.workers above 0 needs. passed, when given,
    takes each viewer relay.budget leaves, with the slots its view tracks,
    so anti-ESP keeps its pairs as an ask would. It runs once
--]]

function Relay.start(
	settings: Settings,
	send: (keys: { Key }, data: buffer) -> (),
	sendWithheld: (keys: { Key }, data: buffer) -> (),
	traffic: (key: Key) -> number,
	isHidden: (viewer: Viewer, slot: number) -> boolean,
	answers: ((viewers: { Viewer }) -> Answers)?,
	asked: ((viewer: Viewer, slots: { number }, count: number) -> ())?,
	passed: Passed?
)
	if Started then
		error("Relay.start runs once, and it has already run", 2)
	elseif
		type(send) ~= "function"
		or type(sendWithheld) ~= "function"
		or type(traffic) ~= "function"
		or type(isHidden) ~= "function"
	then
		error("Relay.start takes send, sendWithheld, traffic and isHidden as functions", 2)
	elseif passed ~= nil and type(passed) ~= "function" then
		error(`Relay.start takes anti-ESP's passed as a function or nil, not a {typeof(passed)}`, 2)
	elseif settings.clock ~= nil and type(settings.clock) ~= "function" then
		error(`Relay.start takes its clock as a function or nil, not a {typeof(settings.clock)}`, 2)
	end

	local shared: Shared = settings.shared
	local server: ServerSettings = settings.server
	local relay: { read changes: boolean?, read workers: number?, read clocks: boolean? }? = server.relay

	local workers: number = 0
	if relay and relay.workers then
		workers = relay.workers
	end

	if workers > 0 and type(answers) ~= "function" then
		error("Relay.start takes anti-ESP's answers as a function while relay.workers is above 0", 2)
	elseif workers > 0 and type(asked) ~= "function" then
		error("Relay.start takes anti-ESP's asked as a function while relay.workers is above 0", 2)
	end

	Started = true
	Layout = settings.layout
	Keyed.hash = Fields.hash(settings.layout)
	Keyed.gravity = shared.step.gravity
	Limits = { lean = shared.step.lean, headCone = shared.step.headCone }

	local relayRate: number = shared.rates.relay
	ShotTicks = math.ceil(server.shotNear.seconds * relayRate)
	StrideWalk = server.footsteps.stride.walk
	StrideSprint = server.footsteps.stride.sprint

	for code: number, step: Block.Step in STEPS do
		Earshot[code] = earshot(server.footsteps.range[string.lower(step)])
	end

	-- The cone's half-angle as its cosine squared, so a turn measures it with no square root
	local outOfView: OutOfView? = nil
	local cone: { rate: number, cone: number, radius: number }? = server.tiers.outOfView
	if cone then
		local cosine: number = math.cos(math.rad(cone.cone))
		outOfView = {
			rate = cone.rate,
			radiusSquared = cone.radius ^ 2,
			cosineSquared = cosine * cosine,
			wide = cone.cone > QUARTER_TURN,
		}
	end

	if relay and relay.changes then
		Changes = true
	end

	tune(server.tiers.bands, server.tiers.edges)
	tuneCrowd(server.tiers.crowd)

	-- Each section's ring holds WINDOW_SECONDS of runs
	if relay and relay.clocks then
		Clock.on = true
		Clock.capacity = math.ceil(WINDOW_SECONDS * relayRate)

		for _, name: string in CLOCKS do
			Clock.rings[name] = { times = table.create(Clock.capacity, 0), held = 0, head = 0, last = 0 }
		end
	end

	-- Plain values only, since a worker's setup takes the same table across its Actor's boundary
	local turnSettings: Turn.Settings = {
		relayRate = relayRate,
		enter = server.relevancy.enter,
		leave = server.relevancy.leave,
		sleepers = server.sleepers.radius,
		npcs = server.npcs.range,
		weightNear = server.weights.near,
		weightFar = server.weights.far,
		weightShooter = server.weights.shooter,
		weightCone = server.weights.cone,
		shotRate = server.shotNear.rate,
		soft = server.budget.soft * BYTES_PER_KB,
		hard = server.budget.hard * BYTES_PER_KB,
		npcNearSquared = server.npcs.near ^ 2,
		npcFarRate = server.npcs.farRate,
		earshot = Earshot,
		outOfView = outOfView,
		changes = Changes,
		clocks = Clock.on,
	}

	Send = send
	SendWithheld = sendWithheld
	Traffic = traffic
	IsHidden = isHidden
	Caps.passed = passed
	Caps.clock = settings.clock or os.clock

	Turn.start(turnSettings, {
		send = send,
		sendWithheld = sendWithheld,
		heard = hear,
		traffic = traffic,
		isHidden = isHidden,
		valid = Slots.valid,
		observing = observing,
		observes = observes,
		relayed = relayed,
		withheld = tapWithheld,
	})

	if workers > 0 and answers and asked then
		AnswersOf = answers
		Asked = asked
		UseWorkers = true
		Frozen.records = buffer.create(SLOTS * RECORD_BYTES)
		Frozen.helds = buffer.create(SLOTS * MAX_HELD)
		Frozen.heldLengths = buffer.create(SLOTS)
		Frozen.generations = buffer.create(SLOTS)

		for index: number = 1, workers do
			Hosts[index] = {
				views = 0,
				list = {},
				places = {},
				count = 0,
				watchers = 0,
				hands = {},
				own = buffer.create(0),
				calls = Wire.calls(),
				reader = Wire.reader(Records),
				round = 0,
				failure = nil,
				resend = false,
				sent = 0,
			}
		end

		Workers = Pool.new(workers, WORKERS_FOLDER, script.Remote, turnSettings)
	end
end

-- Whether the record just encoded at an offset of Records changed from its reference, a turn under the threshold
-- left out
local function changed(at: number): boolean
	if
		buffer.readu16(Records, at) ~= buffer.readu16(References, at)
		or buffer.readu32(Records, at + 2) ~= buffer.readu32(References, at + 2)
		or buffer.readu32(Records, at + 6) ~= buffer.readu32(References, at + 6)
		or buffer.readu16(Records, at + 13) ~= buffer.readu16(References, at + 13)
		or buffer.readu8(Records, at + 15) ~= buffer.readu8(References, at + 15)
	then
		return true
	end

	local yaw: number = Sequence.difference(buffer.readu16(Records, at + 10), buffer.readu16(References, at + 10))
	local pitch: number = buffer.readi8(Records, at + 12) - buffer.readi8(References, at + 12)

	return math.abs(yaw) >= YAW_CHANGE or math.abs(pitch) >= PITCH_CHANGE
end

--[[
    Encodes a slot's record once for every viewer: its place, its facing
    and its state word from the state, and its pitch and head offset from
    the command it last stepped, which the step has already held to the cone.
    A rider's place is in its platform's space while platforms holds where
    that platform stands this tick, and in world coordinates otherwise. While
    records go as changes, the history's plane for the run keeps it too
--]]

local function encode(slot: number, state: State, command: Command?, generation: number, platforms: Platforms?)
	local record: Record.Record = Scratch
	record.slot = slot
	record.generation = generation
	record.position = state.position
	record.platform = 0
	record.yaw = state.facing
	record.word = StateWord.pack(state)
	record.lean = state.lean

	local platform: number = state.platform
	if platforms and platform ~= 0 then
		local at: vector? = platforms[platform]
		if at then
			record.platform = platform
			record.position = state.position - at
		end
	end

	if command then
		record.pitch = command.pitch
		record.headYaw = command.headYaw
		record.headPitch = command.headPitch
	else
		record.pitch = 0
		record.headYaw = 0
		record.headPitch = 0
	end

	local at: number = slot * RECORD_BYTES
	Record.write(record, Records, at, Limits)

	if Changes then
		buffer.copy(World.history, ((Run % DEPTH) * SLOTS + slot) * RECORD_BYTES, Records, at, RECORD_BYTES)
	end

	if changed(at) then
		buffer.copy(References, at, Records, at, RECORD_BYTES)
		buffer.writeu32(Changed, slot * 4, RunTick)
	end
end

-- Whether length bytes of packed match those of kept from at
local function same(packed: buffer, kept: buffer, at: number, length: number): boolean
	for index: number = 0, length - 1 do
		if buffer.readu8(packed, index) ~= buffer.readu8(kept, at + index) then
			return false
		end
	end

	return true
end

-- A copy of length bytes of source from at, in a buffer of its own
local function slice(source: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, source, at, length)

	return part
end

--[[
    Packs a slot's held item from its state and moves its version on when
    the bytes differ from the last run's, marking it for the workers' next
    hand-in. An empty table holds nothing, which travels as a held part of
    length 0
--]]

local function hold(slot: number, held: Values)
	local length: number = 0
	if next(held) ~= nil then
		length = Fields.write(Layout.held, held, HeldScratch, 0)
	end

	local at: number = slot * MAX_HELD
	local kept: number = buffer.readu8(HeldLengths, slot)
	if length == kept and same(HeldScratch, Helds, at, length) then
		return
	end

	-- The change is handed to the taps while the held item before it is still there
	if Taps.reliable then
		Taps.held(slot, slice(Helds, at, kept), slice(HeldScratch, 0, length))
	end

	buffer.copy(Helds, at, HeldScratch, 0, length)
	buffer.writeu8(HeldLengths, slot, length)
	buffer.writeu16(HeldVersions, slot * 2, (buffer.readu16(HeldVersions, slot * 2) + 1) % WRAP)

	if Workers then
		Header.heldCount += 1
		Header.helds[Header.heldCount] = slot
	end
end

-- Marks a slot whose look or Invisible mark changed for the workers' next hand-in
local function mark(slot: number)
	if Workers and buffer.readu8(Marked, slot) == 0 then
		buffer.writeu8(Marked, slot, 1)
		Header.lookCount += 1
		Header.looks[Header.lookCount] = slot
	end
end

-- Encodes one footstep of a slot's, unless the game gives its kind no range, the run's buffers doubled when full
local function emit(slot: number, kind: number, at: vector, material: Enum.Material)
	if Earshot[kind] == SILENT then
		return
	end

	if Steps.count == Steps.capacity then
		Turn.room(Steps.count + 1)
	end

	local index: number = Steps.count
	Steps.count = index + 1

	buffer.writeu16(Steps.slots, index * 2, slot)
	buffer.writeu8(Steps.kinds, index, kind)
	Steps.places[index + 1] = at

	Footstep.at = at
	Footstep.kind = STEPS[kind]
	Footstep.material = material
	Block.writeFootstep(Footstep, Steps.data, index * FOOTSTEP_BYTES)
end

-- Whether a state stands in a gait that steps: on the ground standing or in a crouch slide, and walking, so a crouch,
-- a crawl, a swim, a climb, a mantle and the staff modes are silent
local function stepping(state: State): boolean
	if not state.grounded or state.moveMode ~= "Walk" then
		return false
	end

	return state.mode == "Slide" or (state.mode == "Ground" and state.posture == "Stand")
end

--[[
    Times a slot's footsteps from the distance it covered since the last
    run: one each time it covers its gait's stride, where the stride ended
    along the way, and one for each jump where it left the ground and each
    landing where it came down. A new life or epoch, as a teleport makes,
    covers no ground
--]]

local function walk(slot: number, state: State, generation: number)
	local positions: { vector } = Samples.positions
	local materials: { Enum.Material } = Samples.materials
	local runs: buffer = Samples.runs
	local lives: buffer = Samples.lives
	local epochs: buffer = Samples.epochs
	local jumped: buffer = Samples.jumps
	local landed: buffer = Samples.lands
	local gaits: buffer = Samples.stepping
	local walked: buffer = Samples.walked
	local index: number = slot + 1
	local position: vector = state.position
	local previous: vector = positions[index]
	local sampled: number = buffer.readu32(runs, slot * 4)

	-- Only a sample from the run before, of the same life and epoch, makes a stretch of ground covered
	local followed: boolean = sampled ~= 0 and sampled == Run - 1 and buffer.readu8(lives, slot) == generation
	if followed and buffer.readu8(epochs, slot) == state.epoch then
		local jumps: number = (state.jumps - buffer.readu8(jumped, slot)) % COUNTERS
		for _ = 1, jumps do
			emit(slot, JUMP, previous, materials[index])
		end

		local lands: number = (state.lands - buffer.readu8(landed, slot)) % COUNTERS
		for _ = 1, lands do
			emit(slot, LAND, position, state.groundMaterial)
		end

		if stepping(state) and buffer.readu8(gaits, slot) == 1 then
			local stride: number = StrideWalk
			local kind: number = WALK
			if state.sprint or state.mode == "Slide" then
				stride = StrideSprint
				kind = SPRINT
			end

			local x: number = position.x - previous.x
			local z: number = position.z - previous.z
			local length: number = math.sqrt(x * x + z * z)

			if length > 0 then
				-- Each step falls where the distance since the last one reaches a stride
				local along: number = math.max(stride - buffer.readf64(walked, slot * 8), 0)

				while along <= length do
					local share: number = along / length
					local at: vector = vector.create(
						Math.lerp(previous.x, position.x, share),
						Math.lerp(previous.y, position.y, share),
						Math.lerp(previous.z, position.z, share)
					)

					emit(slot, kind, at, state.groundMaterial)
					along += stride
				end

				buffer.writef64(walked, slot * 8, length - (along - stride))
			end
		end
	end

	positions[index] = position
	buffer.writeu32(runs, slot * 4, Run)
	buffer.writeu8(lives, slot, generation)
	buffer.writeu8(epochs, slot, state.epoch)
	buffer.writeu8(jumped, slot, state.jumps)
	buffer.writeu8(landed, slot, state.lands)

	if stepping(state) then
		buffer.writeu8(gaits, slot, 1)
	else
		buffer.writeu8(gaits, slot, 0)
	end

	if state.grounded then
		materials[index] = state.groundMaterial
	end
end

-- A key's id, given the first time a hand-in or a result needs it
local function idOf(key: Key): number
	local kept: number? = Ids[key]
	if kept then
		return kept
	end

	NextId += 1
	Ids[key] = NextId
	Keys[NextId] = key

	return NextId
end

--[[
    Homes a key's view the first time Turn would make it: on the ready
    worker with the fewest views, the lowest on ties, while the workers are
    on, and in the in-process Turn otherwise. A view never moves
--]]

local function made(key: Key)
	if Homes[key] ~= nil then
		return
	end

	local home: number = 0
	local pool: Pool? = Workers
	if pool and UseWorkers then
		for index: number, host: Worker in Hosts do
			if pool:isReady(index) and (home == 0 or host.views < Hosts[home].views) then
				home = index
			end
		end
	end

	Homes[key] = home
	if home ~= 0 then
		Hosts[home].views += 1
		Copies[key] = Wire.copy()
	end
end

-- Keeps what a keyframe reads of the world as the last run left it, before this run's walk writes over it
local function freeze()
	Frozen.tick = TickWire
	buffer.copy(Frozen.records, 0, Records)
	buffer.copy(Frozen.helds, 0, Helds)
	buffer.copy(Frozen.heldLengths, 0, HeldLengths)
	buffer.copy(Frozen.generations, 0, Generations)
end

--[[
    Hands each viewer to its home's list, the in-process Turn's or its
    worker's, and a watcher of a worker's view to that worker too, where its
    watch runs, with what the front's loops would work out for it. A worker
    viewer the run's budget leaves goes to no list. Gives whether any viewer
    went to a worker
--]]

local function split(viewers: { Viewer }): boolean
	local homes: { number } = Dispatch.homes
	local places: { number } = Dispatch.places
	local targets: { number } = Dispatch.targets
	local ordinals: { number } = Dispatch.ordinals
	local starting: { boolean } = Dispatch.starting
	local returning: { boolean } = Dispatch.returning
	local budgeted: boolean = Caps.running ~= nil

	for _, host: Worker in Hosts do
		host.count = 0
		host.watchers = 0
	end

	local inProcess: number = 0
	local any: boolean = false

	for index: number, viewer: Viewer in viewers do
		local key: Key = viewer.key
		local target: Key? = viewer.target
		local home: number? = Homes[key]
		if home == nil then
			error("A relay viewer was handed to its home before its view was homed")
		end

		homes[index] = home
		Dispatch.watched[index] = target or false
		targets[index] = 0
		starting[index] = false
		returning[index] = false

		if home == 0 then
			inProcess += 1
			InProcess[inProcess] = viewer
		elseif budgeted and Caps.away[key] then
			continue
		else
			local host: Worker = Hosts[home]
			host.count += 1
			host.list[host.count] = viewer
			host.places[host.count] = index
			places[index] = host.count
			any = true

			if target ~= nil then
				host.watchers += 1
			else
				returning[index] = Watching[key] ~= nil
			end
		end

		-- Its watch runs where its target's view is, at its place among the watchers handed there
		if target ~= nil then
			local targetHome: number? = Homes[target]
			if targetHome ~= nil and targetHome ~= 0 then
				local host: Worker = Hosts[targetHome]
				if targetHome ~= home then
					host.count += 1
					host.list[host.count] = viewer
					host.places[host.count] = index
					host.watchers += 1
				end

				targets[index] = targetHome
				ordinals[index] = host.watchers
				starting[index] = Watching[key] ~= target
				any = true
			elseif targetHome == 0 and home ~= 0 then
				inProcess += 1
				InProcess[inProcess] = viewer
			end
		end
	end

	-- Each list cut to this run's, so a viewer that left is held nowhere
	trim(InProcess, inProcess)
	for _, host: Worker in Hosts do
		trim(host.list, host.count)
	end

	return any
end

-- Puts every slot whose look, Invisible mark or held item was ever set in the header's marks, for a worker whose
-- world missed a run or never had one
local function everything()
	local looks: number, helds: number = 0, 0

	for slot: number = 0, SLOTS - 1 do
		if
			buffer.readu16(LookVersions, slot * 2) ~= 0
			or buffer.readu8(LookLives, slot) ~= 0
			or buffer.readu8(Invisible, slot) ~= 0
		then
			looks += 1
			Header.looks[looks] = slot
		end

		if buffer.readu16(HeldVersions, slot * 2) ~= 0 or buffer.readu8(HeldLengths, slot) ~= 0 then
			helds += 1
			Header.helds[helds] = slot
		end
	end

	Header.lookCount = looks
	Header.heldCount = helds
end

-- The hand kept for a place in a worker's list, made the first time the list is that long
local function handAt(hands: { Hand }, place: number): Hand
	local kept: Hand? = hands[place]
	if kept then
		return kept
	end

	local fresh: Hand = {
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
	hands[place] = fresh

	return fresh
end

--[[
    A viewer as its worker's hand-in carries it: what the front's watch
    loop or turn loop would hand its watch or turn, Volt's traffic and
    whether the budget left it the run before for one whose turn runs, the
    team of its own slot, and its row of anti-ESP's answers by its place in
    the run's viewers
--]]

local function fill(hand: Hand, viewer: Viewer, at: number, teams: buffer)
	local key: Key = viewer.key
	local target: Key? = viewer.target
	local slot: number? = viewer.slot

	hand.id = idOf(key)
	hand.slot = slot
	hand.position = viewer.position
	hand.look = viewer.look
	hand.acknowledged = viewer.acknowledged
	hand.received = viewer.received
	hand.row = (at - 1) * ROW_BYTES
	hand.sequence = 0
	hand.back = false
	hand.zoomed = viewer.zoomed == true
	hand.missed = false
	hand.traffic = 0

	-- A slot the slot table never has goes as it is, so the worker's turn refuses it as the in-process one does
	hand.team = NO_TEAM
	if slot ~= nil and Slots.valid(slot) then
		hand.team = buffer.readf64(teams, slot * 8)
	end

	-- A target with no view gets no id, as 0, which no key has and whose watch finds nothing
	if target ~= nil then
		hand.target = 0
		if Homes[target] ~= nil then
			hand.target = idOf(target)
		end

		if Dispatch.starting[at] then
			hand.sequence = Heard[key] or 0
		end
	else
		hand.target = nil
		hand.traffic = Traffic(key)
		hand.missed = Caps.lefts[key] == Run - 1

		if Dispatch.returning[at] then
			hand.back = true
			hand.sequence = Heard[key] or 0
		end
	end
end

-- Adds seconds to the section of the running run's clocks at an offset
local function add(at: number, seconds: number)
	buffer.writef64(Clock.laps, at, buffer.readf64(Clock.laps, at) + seconds)
end

-- Adds the seconds since the lap being timed began to a section of the running run's clocks, and begins the next lap
local function lap(name: string)
	local now: number = os.clock()
	add(CLOCK_AT[name], now - Clock.from)
	Clock.from = now
end

--[[
    Sends the run's round: anti-ESP's answers for the run's viewers, the
    shared hand-in, carrying every slot's look and held item for a worker
    that missed a run, and each ready worker's own, even with no viewer,
    so its world never falls behind
--]]

local function dispatch(pool: Pool, viewers: { Viewer })
	local clocked: boolean = Clock.on
	local answers: Answers = AnswersOf(viewers)
	if clocked then
		lap("answers")
	end

	local header: Wire.Shared = Header

	for index: number, host: Worker in Hosts do
		if pool:isReady(index) and host.sent ~= Run - 1 then
			everything()
			break
		end
	end

	header.run = Run
	header.tick = RunTick
	header.elapsed = Elapsed
	header.wire = TickWire
	header.observing = Taps.observing
	header.observedCount = 0
	header.kinds = answers.kinds
	header.teams = answers.teams

	-- Only a viewer handed in can be one of a turn's recipients, so only those are named as observed
	if Taps.observing then
		for _, viewer: Viewer in viewers do
			One[1] = viewer.key
			if Taps.observes(One, 1) then
				header.observedCount += 1
				header.observed[header.observedCount] = idOf(viewer.key)
			end
		end
	end

	local shared: buffer = Wire.writeShared(World, header)
	if clocked then
		lap("shared")
	end

	-- Every hand-in written before any goes out, so a port that throws on the way leaves no round out and loses no mark
	-- or call
	for index: number, host: Worker in Hosts do
		if pool:isReady(index) then
			local hands: { Hand } = host.hands
			for place: number = 1, host.count do
				fill(handAt(hands, place), host.list[place], host.places[place], answers.teams)
			end

			host.own = Wire.writeOwn(host.calls, hands, host.count, answers.visible, answers.quiet, host.resend)
		end
	end

	buffer.fill(Marked, 0, 0)
	header.lookCount = 0

	-- The list as it is sent, which the finish reads in its order however the caller's own list changes meanwhile
	table.move(viewers, 1, #viewers, 1, RunViewers)
	trim(RunViewers, #viewers)

	if clocked then
		lap("own")
	end

	Round += 1
	for index: number, host: Worker in Hosts do
		host.round = 0

		if pool:isReady(index) then
			local sent: boolean, failure: unknown = pcall(pool.send, pool, index, Round, shared, host.own)

			-- A send that throws gives the round up, each worker already sent it sending its views whole next
			if not sent then
				for _, other: Worker in Hosts do
					if other.round ~= 0 then
						other.round = 0
						other.resend = true
					end
				end

				error(failure, 0)
			end

			host.calls.count = 0
			host.round = Round
			host.sent = Run

			-- From this hand-in on its worker sends each view whole the next time it runs it
			if host.resend then
				host.resend = false
				for key: Key, home: number in Homes do
					if home == index then
						Stale[key] = true
					end
				end
			end
		end
	end

	-- A key removed and not handed in again lets its id go now that every worker has been sent its removal
	for key: Key in Leaving do
		local id: number? = Ids[key]
		if id ~= nil and Homes[key] == nil then
			Ids[key] = nil
			Keys[id] = nil
		end
	end

	table.clear(Leaving)
	Out = true

	-- The dispatch ends here, where the round's wait and each worker's delivery are measured from
	if clocked then
		lap("handIn")
		Clock.dispatched = Clock.from
	end
end

--[[
    Keeps the run before's clocks in their rings, each over its oldest once
    full, and starts the running run's from 0
--]]

local function keep()
	if Clock.pending then
		local capacity: number = Clock.capacity

		for index: number, name: string in CLOCKS do
			local ring: ClockRing = Clock.rings[name]
			local took: number = buffer.readf64(Clock.laps, (index - 1) * 8)

			ring.times[ring.head + 1] = took
			ring.head = (ring.head + 1) % capacity
			ring.held = math.min(ring.held + 1, capacity)
			ring.last = took
		end
	end

	buffer.fill(Clock.laps, 0, 0)
	Clock.pending = true
	Clock.landed = 0
	Clock.workers = 0
end

--[[
    Puts the places from 1 of the run's turn viewers homed in process, or
    on the workers, in the order the budget takes them: those it left in
    one of its last LEFT_EVERY - 1 runs, whose turns it forces, first in the
    list's order, then the rest from the cursor round, each marked free when
    the budget may leave it. Gives how many there are and how many are free;
    a run leaves at most a LEFT_EVERY'th of the first, rounded down
--]]

local function rank(viewers: { Viewer }, onWorkers: boolean): (number, number)
	local order: { number } = Caps.order
	local free: { boolean } = Caps.free
	local count: number = #viewers
	local placed: number, total: number, frees: number = 0, 0, 0
	local forcedFrom: number = Run - LEFT_EVERY -- A viewer left after this run is forced

	for index: number, viewer: Viewer in viewers do
		local at: number? = Caps.lefts[viewer.key]
		if viewer.target == nil and (Homes[viewer.key] ~= 0) == onWorkers then
			total += 1
			if at ~= nil and at > forcedFrom then
				placed += 1
				order[placed] = index
				free[placed] = false
			end
		end
	end

	for step: number = 0, count - 1 do
		local index: number = (Caps.cursor - 1 + step) % count + 1
		local viewer: Viewer = viewers[index]
		local key: Key = viewer.key
		local at: number? = Caps.lefts[key]
		local forced: boolean = at ~= nil and at > forcedFrom
		if viewer.target == nil and (Homes[key] ~= 0) == onWorkers and not forced then
			-- None a viewer this run watches, whose watchers need its turn, and none back from a spectate
			local leavable: boolean = Caps.guarded[key] == nil and Watching[key] == nil
			placed += 1
			order[placed] = index
			free[placed] = leavable
			if leavable then
				frees += 1
			end
		end
	end

	trim(order, placed)
	trim(free, placed)

	return total, frees
end

-- Leaves a viewer's turn to the next run, where it goes first, marked as following a missed one: its credit counts
-- every relay tick since its last turn, held to Turn's most, and it can hear this run's footsteps a run late, an
-- enemy's not marked Invisible in it, as a Parked one is, while still culled from it in the same life and kind, in
-- earshot of where it then stands, and for a view on a worker only if the worker took this run
local function leave(viewer: Viewer, index: number, count: number)
	local key: Key = viewer.key
	Caps.lefts[key] = Run
	Caps.left += 1
	Caps.totalLeft += 1
	Caps.first = math.min(Caps.first, (index - Caps.cursor) % count)
end

--[[
    Picks the run's worker turns its budget hands in, each it forces or may
    not leave and as many of the rest as the last measure allows, but never
    fewer than all less a LEFT_EVERY'th of them, rounded down, before any
    hand-in is written, and leaves the others, the last in its order, whom
    the finish passes to anti-ESP in the turns' place
--]]

local function choose(viewers: { Viewer })
	local total: number, frees: number = rank(viewers, true)
	local hand: number = Caps.hand or total
	local allowed: number = math.min(total // LEFT_EVERY, math.max(total - hand, 0), frees)
	local remaining: number = frees
	local count: number = #viewers

	table.clear(Caps.away)
	for place: number, index: number in Caps.order do
		local viewer: Viewer = viewers[index]
		if Caps.free[place] then
			if remaining <= allowed then
				Caps.away[viewer.key] = true
				leave(viewer, index, count)
			end

			remaining -= 1
		end
	end

	Caps.handed = total - allowed
end

-- An in-process viewer's turn, one back from a spectate going on past what its client was sent, and one the run
-- before left marked as following a missed one
local function turnAt(viewer: Viewer)
	local key: Key = viewer.key
	local back: number? = nil
	if Watching[key] ~= nil then
		back = Heard[key] or 0
		Watching[key] = nil
	end

	Turn.turn(viewer, back, Caps.lefts[key] == Run - 1)
end

--[[
    The in-process turns under a budget: those it forces, then the rest from
    the cursor, each that may be left first reading whether the run has
    reached its budget. Once it has, the last of them in that order, up to a
    LEFT_EVERY'th of the in-process turns, are left, each passed to
    anti-ESP in its turn's place with the slots its view tracks, so the
    pairs its last turn asked about stay asked
--]]

local function budgetedTurns(viewers: { Viewer }, budget: number)
	local total: number, frees: number = rank(viewers, false)
	local allowed: number = math.min(total // LEFT_EVERY, frees)
	local remaining: number = frees
	local reached: boolean = false
	local count: number = #viewers

	for place: number, index: number in Caps.order do
		local viewer: Viewer = viewers[index]
		local away: boolean = false

		if allowed > 0 and Caps.free[place] then
			if not reached then
				reached = Caps.clock() - Caps.began >= budget
			end

			away = reached and remaining <= allowed
			remaining -= 1
		end

		if away then
			local view: View? = Turn.view(viewer.key)
			if view == nil then
				error("A relay viewer in process was left with no view after Turn.ready")
			end

			leave(viewer, index, count)

			local passed: Passed? = Caps.passed
			if passed then
				passed(viewer, view.tracked, #view.tracked)
			end
		else
			turnAt(viewer)
		end
	end
end

--[[
    Counts a run the budget it began under judged, over when the budget
    left a viewer in it or its measure passed the budget, into the runs over
    and under in a row, which lower the farthest band once tiers.underLoad's
    runs in a row are over and put it back once as many in a row are under
--]]

local function judge(over: boolean)
	if over then
		Caps.totalOver += 1
		Caps.overs += 1
		Caps.unders = 0
	else
		Caps.unders += 1
		Caps.overs = 0
	end

	local underLoad: UnderLoad? = Caps.underLoad
	if underLoad == nil then
		return
	end

	if not Caps.lowered and Caps.overs >= underLoad.runs then
		Caps.lowered = true
		lowerFar()
	elseif Caps.lowered and Caps.unders >= underLoad.runs then
		Caps.lowered = false
		lowerFar()
	end
end

--[[
    One relay tick: encodes each live body's record and footsteps once, a
    rider's in its platform's space where platforms holds that platform's
    place at the tick, and files the body by where it stands, then gives
    each viewer with no target its blocks, copied to the viewers watching
    it. states holds the server's live bodies by slot, and commands the
    command each last stepped, whose pitch and head offset its record
    carries. A target handed more watchers than it takes errors, naming
    it, once every viewer has had its turn, and a tick, unwrapped, no later
    than the last run's is refused. With workers, their turns go out in a
    round Relay.finish brings in, and no run starts while one is out. With
    relay.clocks on, the run before's clocks go into their rings first.
    Under relay.budget the viewers it left in its last runs go first, and
    those it leaves this run, at most a quarter of each mode's, wait for
    the next, where each can hear this run's footsteps a run late: an
    enemy's not marked Invisible in it, as a Parked one is, while still
    culled from it in the same life and kind, in earshot of where it then
    stands, and for a view on a worker only if the worker took this run
--]]

function Relay.run(
	tick: number,
	viewers: { Viewer },
	states: { [number]: State },
	commands: { [number]: Command },
	platforms: Platforms?
)
	if not Started then
		error("Relay.run ran before Relay.start", 2)
	elseif Out then
		error("Relay.run ran while the last run's round was still out, before Relay.finish or Relay.drop", 2)
	elseif not (tick > RunTick) then
		error(`Relay.run takes a relay tick after the last run's {RunTick}, not {tick}`, 2)
	end

	-- The budget the run begins under is the one its finish judges it by, so long as no seam is called meanwhile. A
	-- run before that left a viewer has its footsteps kept for that viewer's next turn, which is this run's
	local budget: number? = Caps.budget
	local carry: boolean = Caps.left > 0
	Caps.running = budget
	Caps.ranAfter = Caps.sets
	Caps.left = 0
	if budget ~= nil then
		Caps.began = Caps.clock()
		Caps.first = math.huge
	end

	if Caps.lowered and Bands.tuning.bands > 1 then
		Caps.halved += 1
	end

	local clocked: boolean = Clock.on
	if clocked then
		keep()
		Clock.from = os.clock()
	end

	local pool: Pool? = Workers
	if pool then
		freeze()
	end

	Run += 1
	Elapsed = tick - RunTick
	RunTick = tick
	TickWire = tick % WRAP
	Live.tick = TickWire
	Header.heldCount = 0
	Overfull = nil
	Turn.begin(Run, RunTick, Elapsed, TickWire, Bands.tuning, carry)
	Steps.count = 0

	-- Each body's facts where every turn reads them, numbered in the order the states are walked, which each turn
	-- keeps. One in the states with no entry is still marked unless Parked, as a withheld block asks only that
	local order: number = 0

	for slot: number, state: State in states do
		local generation: number, entry: Slots.Entry? = Slots.get(slot)
		if state.moveMode ~= "Parked" then
			buffer.writeu32(Unparked, slot * 4, Run)
		end

		if not entry then
			continue
		end

		local kind: number = KIND_CODES[entry.kind]

		buffer.writeu32(Present, slot * 4, Run)
		buffer.writeu8(Generations, slot, generation)
		buffer.writeu8(Kinds, slot, kind)

		encode(slot, state, commands[slot], generation, platforms)
		hold(slot, state.held)

		if kind == PLAYER or kind == NPC then
			walk(slot, state, generation)
		end

		Positions[slot + 1] = state.position
		buffer.writef64(Facings, slot * 8, state.facing)

		order += 1
		buffer.writeu16(Walk, order * 2, slot)
	end

	if clocked then
		lap("walk")
	end

	Turn.file(order)
	Header.places = order

	if clocked then
		lap("file")
	end

	-- Every view homed where Turn makes it, in the list's order, among the workers ready now
	if pool then
		pool:ready()
	end

	for _, viewer: Viewer in viewers do
		made(viewer.key)
	end

	-- Under a budget, the targets watched this run are never left, and the worker turns it leaves go to no worker
	if budget ~= nil then
		table.clear(Caps.guarded)
		for _, viewer: Viewer in viewers do
			local target: Key? = viewer.target
			if target ~= nil then
				Caps.guarded[target] = true
			end
		end

		Caps.handed = 0
		if pool then
			choose(viewers)
		end
	end

	local dispatched: boolean = split(viewers)
	Turn.ready(InProcess)

	-- Each watcher of an in-process view joins its target's recipients, its target's blocks numbered past the newest
	-- its client was sent elsewhere the run its watch starts
	for index: number, viewer: Viewer in viewers do
		local target: Key? = viewer.target
		if target ~= nil and Dispatch.targets[index] == 0 then
			local key: Key = viewer.key
			local starting: boolean = Watching[key] ~= target
			local latest: number = 0
			if starting then
				latest = Heard[key] or 0
			end

			local watched: boolean? = Turn.watch(viewer, target, latest)
			if watched == false then
				if Overfull == nil then
					Overfull = target
					OverfullAt = index
				end
			elseif watched and starting then
				Watching[key] = target
			end
		end
	end

	-- Each in-process viewer with no target takes its turn in the list's order, or under a budget in the budget's,
	-- and the next run's rest begin at the first it left
	if budget == nil then
		for index: number, viewer: Viewer in viewers do
			if viewer.target == nil and Dispatch.homes[index] == 0 then
				turnAt(viewer)
			end
		end
	else
		budgetedTurns(viewers, budget)

		if Caps.first ~= math.huge then
			Caps.cursor = (Caps.cursor - 1 + Caps.first) % #viewers + 1
		end
	end

	-- The in-process turns' parts join the workers' at the front of the run's clocks
	if clocked then
		local turns: buffer = Turn.clocks()
		for at: number = 0, buffer.len(turns) - 8, 8 do
			add(at, buffer.readf64(turns, at))
		end

		lap("inProcess")
	end

	-- The run's own seconds under a budget, which a round out adds its finish's to before the run is judged
	if pool and dispatched then
		dispatch(pool, viewers)
		if budget ~= nil then
			Caps.measured = Caps.clock() - Caps.began
		end

		return
	end

	-- A run no worker takes leaves every worker behind, so its next hand-in carries every mark anyway
	if pool then
		buffer.fill(Marked, 0, 0)
		Header.lookCount = 0
	end

	if budget ~= nil then
		judge(Caps.left > 0 or Caps.clock() - Caps.began > budget)
	end

	local overfull: Key? = Overfull
	if overfull ~= nil then
		Overfull = nil
		error(`{overfull.Name} has more than the {MAX_WATCHERS} watchers one target takes`, 2)
	end
end

--[[
    Replays one worker turn through the front's own ports, as its turn
    called them: its asks of anti-ESP in walk order, then its marks' slots
    in walk order in one call to asked, then its blocks, taps, heard
    sequences and withheld blocks, to its recipients by key
--]]

local function replay(viewer: Viewer, reader: Reader)
	local clocked: boolean = Clock.on
	local count: number = reader.recipientCount
	local recipients: { number } = reader.recipients

	for index: number = 1, count do
		local key: Key? = Keys[recipients[index]]
		if key == nil then
			error("A relay worker's result names a recipient the front holds no key for")
		end

		Recipients[index] = key
		if index > 1 then
			Watchers[index - 1] = key
		end
	end

	trim(Recipients, count)
	trim(Watchers, count - 1)

	for index: number = 1, Wire.asks(reader, Places) do
		IsHidden(viewer, buffer.readu16(Walk, Places[index] * 2))
	end

	-- A mark only stamps its pair asked, which no ask of another pair reads, so the marks follow the turn's asks
	local marks: number = Wire.marks(reader, Places)
	if marks > 0 then
		for index: number = 1, marks do
			Places[index] = buffer.readu16(Walk, Places[index] * 2)
		end

		Asked(viewer, Places, marks)
	end

	if clocked then
		lap("asks")
	end

	local kind: number = Wire.nextEvent(reader)
	while kind ~= 0 do
		if kind == Wire.SEND then
			Send(Recipients, reader.block)
		elseif kind == Wire.RELAYED then
			relayed(Recipients, count, reader.tap, reader.block)
		elseif kind == Wire.HEARD then
			hear(Recipients, count, reader.sequence)
		elseif kind == Wire.WITHHELD then
			SendWithheld(Watchers, reader.block)
		else
			tapWithheld(Recipients[1], reader.tap, reader.block)
		end

		kind = Wire.nextEvent(reader)
	end

	if clocked then
		lap("sends")
	end
end

--[[
    Replays the round's worker turns in viewer order, each turn's asks,
    blocks and taps, up to one that threw or whose worker's run threw, and
    gives the first failure's text, nil for none. A viewer the run's budget
    left took no turn, so in its place it is passed to anti-ESP, inside the
    hold, with the slots its copy tracks, so the pairs its last turn asked
    about stay asked
--]]

local function replayTurns(viewers: { Viewer }): string?
	local homes: { number } = Dispatch.homes
	local places: { number } = Dispatch.places
	local watched: { Key | false } = Dispatch.watched
	local budgeted: boolean = Caps.running ~= nil
	local passed: Passed? = Caps.passed

	local failure: string? = nil
	for index: number, viewer: Viewer in viewers do
		local home: number = homes[index]
		if watched[index] ~= false or home == 0 then
			continue
		elseif budgeted and Caps.away[viewer.key] then
			local copy: Copy? = Copies[viewer.key]
			if copy == nil then
				error("A relay viewer on a worker was left with no copy of its view")
			elseif passed then
				passed(viewer, copy.tracked, #copy.tracked)
			end
		else
			local host: Worker = Hosts[home]
			failure = host.failure
			if failure ~= nil then
				break
			end

			local reader: Reader = host.reader
			if not Wire.nextTurn(reader) or reader.place ~= places[index] then
				error("A relay worker's result holds its turns out of the front's order")
			end

			replay(viewer, reader)
			if reader.failed == reader.place then
				failure = reader.failure
				break
			end
		end
	end

	-- A worker that took no turn still raises what its run threw
	for _, host: Worker in Hosts do
		if failure == nil and host.failure ~= nil then
			failure = host.failure
		end
	end

	return failure
end

--[[
    Takes in the round's results: each watch's answer in viewer order, the
    copies and the counts, the returns from a spectate the workers ran, and
    then the worker turns, so a port that throws in the replay leaves the
    copies level. Gives the first failure's text, and what a port threw
--]]

local function land(viewers: { Viewer }): (string?, unknown)
	local homes: { number } = Dispatch.homes
	local places: { number } = Dispatch.places
	local targets: { number } = Dispatch.targets

	for index: number, viewer: Viewer in viewers do
		local target: Key | false = Dispatch.watched[index]
		local home: number = targets[index]
		if target ~= false and home ~= 0 and Hosts[home].failure == nil then
			local answer: boolean? = Wire.watched(Hosts[home].reader, Dispatch.ordinals[index])
			if answer == false then
				if Overfull == nil or index < OverfullAt then
					Overfull = target
					OverfullAt = index
				end
			elseif answer and Dispatch.starting[index] then
				Watching[viewer.key] = target
			end
		end
	end

	for _, host: Worker in Hosts do
		if host.round ~= 0 and host.failure == nil then
			local reader: Reader = host.reader
			local id: number = Wire.nextView(reader)

			while id ~= 0 do
				local key: Key? = Keys[id]
				if key == nil then
					error("A relay worker's result holds a view of a key the front has let go")
				end

				-- A view sent whole goes into an empty copy, as its worker's shadow of it started again
				if Stale[key] then
					Copies[key] = Wire.copy()
					Stale[key] = nil
				end

				local copy: Copy? = Copies[key]
				if copy == nil then
					error("A relay worker's result holds a view the front keeps no copy of")
				end

				Wire.applyView(reader, copy)
				Revealed[key] = nil
				id = Wire.nextView(reader)
			end

			Totals.sent += reader.sent
			Totals.cut += reader.cut
			Totals.visited += reader.visited
			Totals.rest += reader.rest
		end

		host.round = 0
	end

	-- Each viewer back from a spectate whose turn its worker took comes back to its own view
	for index: number, viewer: Viewer in viewers do
		if Dispatch.returning[index] then
			local host: Worker = Hosts[homes[index]]
			local failed: number = host.reader.failed
			if host.failure == nil and (failed == 0 or places[index] <= failed) then
				Watching[viewer.key] = nil
			end
		end
	end

	if Clock.on then
		lap("land")
	end

	local replayed: boolean, failure: unknown = pcall(replayTurns, viewers)
	if not replayed then
		return nil, failure
	end

	return failure :: string?, nil
end

-- Errors naming a value that is no slot, from the caller of the member named
local function checkSlot(slot: number, member: string)
	if not Slots.valid(slot) then
		error(`Relay.{member} takes one of the slot table's slots, not {slot}`, 3)
	end
end

-- Whether a viewer's stretch of a slot belongs to the slot's current life and the viewer is sent it, which a
-- viewer watching a target, its own view set aside, never is
local function sentTo(key: Key, view: Seen, slot: number, generation: number): boolean
	return Watching[key] == nil
		and bit32.btest(buffer.readu16(view.flags, slot * 2), SENT)
		and buffer.readu8(view.generations, slot) == generation
end

-- A key's view by its home: the in-process Turn's own, or the front's copy of a worker's
local function viewAt(key: Key, home: number): Seen?
	if home == 0 then
		return Turn.view(key)
	end

	return Copies[key]
end

-- A key's view, nil before its first
local function viewFor(key: Key): Seen?
	local home: number? = Homes[key]
	if home == nil then
		return nil
	end

	return viewAt(key, home)
end

-- A shooter's raised rate for a viewer, through a relay tick, in the viewer's view
local function shotNearNow(key: Key, slot: number, through: number)
	local home: number? = Homes[key]
	if home == 0 then
		Turn.shotNear(key, slot, through)
	elseif home ~= nil then
		Wire.call(Hosts[home].calls, Wire.SHOT_NEAR, idOf(key), slot, through)
	end
end

-- A fresh pending reveal of a slot's life for every view sent it, its kind kept beside a worker's copy until the
-- worker runs the view, so the copy stays what the worker last told
local function revealNow(slot: number, generation: number)
	for key: Key, home: number in Homes do
		local view: Seen? = viewAt(key, home)
		if view and sentTo(key, view, slot, generation) then
			if home == 0 then
				Turn.reveal(key, slot)
			else
				local revealed: { [number]: number } = Revealed[key] or {}
				Revealed[key] = revealed
				revealed[slot] = buffer.readu8(Kinds, slot)
				Wire.call(Hosts[home].calls, Wire.REVEAL, idOf(key), slot, 0)
			end
		end
	end
end

-- Every slot a view is sent a pending reveal again, from a floor run on, its kinds kept as a reveal keeps them
local function revealAllNow(key: Key, floor: number)
	local home: number? = Homes[key]
	if home == 0 then
		Turn.revealAll(key, floor)

		return
	end

	local copy: Copy? = Copies[key]
	if home == nil or copy == nil then
		return
	end

	local revealed: { [number]: number } = Revealed[key] or {}
	Revealed[key] = revealed

	for _, slot: number in copy.tracked do
		if bit32.btest(buffer.readu16(copy.flags, slot * 2), SENT) then
			revealed[slot] = buffer.readu8(Kinds, slot)
		end
	end

	Wire.call(Hosts[home].calls, Wire.REVEAL_ALL, idOf(key), 0, floor)
end

-- A viewer's render distance from its next turn, its view made where Turn makes one
local function setDistanceNow(key: Key, distance: number)
	made(key)

	local home: number = Homes[key] or 0
	if home == 0 then
		Turn.setDistance(key, distance)
	else
		Wire.call(Hosts[home].calls, Wire.SET_DISTANCE, idOf(key), 0, distance)
	end
end

-- Forgets a viewer that left, its view in every worker ready, its id once its next hand-in has gone out
local function removeNow(key: Key)
	Turn.remove(key)

	local id: number? = Ids[key]
	local pool: Pool? = Workers
	if id ~= nil and pool then
		for index: number, host: Worker in Hosts do
			if pool:isReady(index) then
				Wire.call(host.calls, Wire.REMOVE, id, 0, 0)
			end
		end

		Leaving[key] = true
	end

	local home: number? = Homes[key]
	if home ~= nil and home ~= 0 then
		Hosts[home].views -= 1
	end

	Homes[key] = nil
	Copies[key] = nil
	Revealed[key] = nil
	Stale[key] = nil
	Heard[key] = nil
	Watching[key] = nil
	Caps.lefts[key] = nil
end

-- Keeps a call made while a round is out, with what it worked out at the call, for the end of the finish or drop
local function defer(kind: number, key: Key?, slot: number, value: number)
	local count: number = Deferred.count + 1

	Deferred.count = count
	Deferred.kinds[count] = kind
	Deferred.keys[count] = key
	Deferred.slots[count] = slot
	Deferred.values[count] = value
end

-- Runs the calls kept while the round was out, in call order, as calls made after the run
local function runDeferred()
	local count: number = Deferred.count
	Deferred.count = 0

	for index: number = 1, count do
		local kind: number = Deferred.kinds[index]
		local key: Key? = Deferred.keys[index]
		local slot: number = Deferred.slots[index]
		local value: number = Deferred.values[index]
		Deferred.keys[index] = nil

		if kind == Wire.REVEAL then
			revealNow(slot, value)
		elseif key == nil then
			error("A relay call kept while its round was out lost its viewer")
		elseif kind == Wire.SHOT_NEAR then
			shotNearNow(key, slot, value)
		elseif kind == Wire.REVEAL_ALL then
			revealAllNow(key, value)
		elseif kind == Wire.SET_DISTANCE then
			setDistanceNow(key, value)
		else
			removeNow(key)
		end
	end
end

-- Keeps a section of the running run's clocks as the slowest worker's: the first worker's, then any larger
local function slowest(name: string, seconds: number)
	local at: number = CLOCK_AT[name]
	if Clock.workers == 1 or seconds > buffer.readf64(Clock.laps, at) then
		buffer.writef64(Clock.laps, at, seconds)
	end
end

--[[
    Takes one landed worker's clocks into the running run's: its sections
    added to the other workers', and its run, its last fire, its delivery
    and its back kept as the slowest worker's, the last two across its clock
    and the main thread's. A round it ran with no clocks, as a run that
    threw, adds nothing
--]]

local function clockWorker(pool: Pool, index: number)
	local start: number, finish: number, clocks: buffer?, landed: number, fired: number = pool:times(index)
	if clocks == nil then
		return
	end

	for at: number = 0, Wire.CLOCK_BYTES - 8, 8 do
		add(at, buffer.readf64(clocks, at))
	end

	Clock.workers += 1
	Clock.landed = math.max(Clock.landed, landed)
	slowest("run", finish - start)
	slowest("fire", fired)
	slowest("delivery", start - Clock.dispatched)
	slowest("back", landed - finish)
end

--[[
    Brings the run's round in once every worker it went to has landed it,
    false until then, and true at once with none out: the watches, the
    copies, the counts, each worker turn in viewer order with its asks
    replayed, its marks handed to asked and its blocks sent and tapped, the
    calls made since the run, and last what a port threw, a turn's failure
    or an overfull target. With relay.clocks on it times each of those and
    takes in each worker's clocks. Each viewer the run's budget left is
    passed to anti-ESP in its turn's place. Under the budget the run began
    with, and no seam called since, the run's seconds and its own judge the
    run and set the worker turns the next run hands in: at a budget of 0
    all but the quarter it may leave, and otherwise every one after a run
    that handed none in
--]]

function Relay.finish(): boolean
	if not Out then
		return true
	end

	local pool: Pool? = Workers
	if not pool then
		error("A relay round was out with no workers")
	end

	for index: number, host: Worker in Hosts do
		if host.round ~= 0 then
			local result: buffer?, failure: string? = pool:landed(index, host.round)
			if result == nil and failure == nil then
				return false
			end
		end
	end

	-- The finish's laps begin where the round's wait ends, and under the run's budget so does its share of the measure,
	-- unless a seam was called since the run, whose fresh count and hand-in this run's measure never reaches
	local budget: number? = Caps.running
	if Caps.ranAfter ~= Caps.sets then
		budget = nil
	end

	local finishing: number = 0
	if budget ~= nil then
		finishing = Caps.clock()
	end

	local clocked: boolean = Clock.on
	local began: number = 0
	if clocked then
		began = os.clock()
		Clock.from = began
	end

	Out = false
	for index: number, host: Worker in Hosts do
		host.failure = nil

		if host.round ~= 0 then
			local result: buffer?, failure: string? = pool:landed(index, host.round)
			if result then
				Wire.open(host.reader, result)
			else
				-- Its run may have thrown before it read this run's looks and held items, so its next takes them all
				host.failure = failure
				host.resend = true
				host.sent = 0
			end

			if clocked then
				clockWorker(pool, index)
			end
		end
	end

	-- The round's waits by the main thread's clock: from the dispatch's end to the last result's landing, and on to here
	if clocked then
		if Clock.workers > 0 then
			add(CLOCK_AT.round, Clock.landed - Clock.dispatched)
			add(CLOCK_AT.waitBeat, began - Clock.landed)
		end

		lap("open")
	end

	local failure: string?, thrown: unknown = land(RunViewers)
	local overfull: Key? = Overfull
	Overfull = nil
	runDeferred()

	if clocked then
		lap("deferred")
	end

	-- The run's measure, its own seconds and the finish's, sets the worker turns the next run hands in, before the
	-- share the budget may leave: none at a budget of 0, which every run reaches, else those this run handed in times
	-- the budget over the measure, and every one after a measure of no time or a run that handed none in, which tells
	-- the next nothing
	if budget ~= nil then
		local measure: number = Caps.measured + Caps.clock() - finishing
		local handed: number = Caps.handed
		if budget == 0 then
			Caps.hand = 0
		elseif handed > 0 and measure > 0 then
			Caps.hand = math.floor(handed * budget / measure)
		else
			Caps.hand = nil
		end

		judge(Caps.left > 0 or measure > budget)
	end

	if thrown ~= nil then
		error(thrown, 0)
	elseif failure ~= nil then
		error(failure, 0)
	elseif overfull ~= nil then
		error(`{overfull.Name} has more than the {MAX_WATCHERS} watchers one target takes`, 2)
	end

	return true
end

--[[
    Gives up the run's round, as if every block in it were lost: nothing is
    sent, asked or tapped, the calls made since the run run, and each
    worker it went to sends each view it runs whole from its next run, so
    the copies start again from the workers' own views. A target the
    in-process watches found overfull is still raised. Under the budget
    the run began with, with no seam called since, a run given up counts
    over it, its measure never complete, and the worker turns the next run
    hands in stay as they were
--]]

function Relay.drop()
	if not Out then
		error("Relay.drop ran with no round out", 2)
	end

	Out = false
	if Caps.running ~= nil and Caps.ranAfter == Caps.sets then
		judge(true)
	end

	-- A worker whose round is given up may have thrown before it read the run's looks and held items
	for _, host: Worker in Hosts do
		if host.round ~= 0 then
			host.round = 0
			host.resend = true
			host.sent = 0
		end
	end

	local overfull: Key? = Overfull
	Overfull = nil
	runDeferred()

	if overfull ~= nil then
		error(`{overfull.Name} has more than the {MAX_WATCHERS} watchers one target takes`, 2)
	end
end

--[[
    Sets where the views made from now on go: to the ready workers while on
    and to the in-process Turn while off, for a dev arm that switches modes
    between loads. A view made before stays where it is
--]]

function Relay.useWorkers(on: boolean)
	if type(on) ~= "boolean" then
		error(`Relay.useWorkers takes true or false, not {on}`, 2)
	elseif not Workers then
		error("Relay.useWorkers needs the workers that relay.workers above 0 makes", 2)
	end

	UseWorkers = on
end

--[[
    Where the views are, for a dev run's lines: how many the in-process Turn
    holds, how many each worker does in a list of their own, empty with no
    workers, and how many of the workers are ready
--]]

function Relay.homes(): (number, { number }, number)
	local inProcess: number = 0
	for _, home: number in Homes do
		if home == 0 then
			inProcess += 1
		end
	end

	local views: { number } = {}
	local ready: number = 0
	local pool: Pool? = Workers

	for index: number, host: Worker in Hosts do
		views[index] = host.views
		if pool and pool:isReady(index) then
			ready += 1
		end
	end

	return inProcess, views, ready
end

--[[
    Sets the distance bands and their edges every turn reads from the next
    run on, in process and on every worker alike, refused as the server's
    check refuses tiers.bands and tiers.edges, for a dev run that compares
    two sets of bands on one server. A pair standing inside an edge's slack
    when the edges change keeps the side its stored count of edges gives it
    until it leaves the slack. While the far rate under load holds the
    farthest band lowered, the new farthest band is lowered in its place
--]]

function Relay.setBands(bands: { Band }, edges: { Edge })
	if not Started then
		error("Relay.setBands ran before Relay.start", 2)
	end

	Config.bands(bands, edges)
	tune(bands, edges)
	lowerFar()
end

-- The bands and edges every turn reads, as tiers or Relay.setBands last gave them, each in new lists
function Relay.bands(): ({ Band }, { Edge })
	local bands: { Band } = {}
	for index: number, band: Band in Bands.given do
		bands[index] = { aim = band.aim, floor = band.floor }
	end

	local edges: { Edge } = {}
	for index: number, edge: Edge in Bands.edges do
		edges[index] = { enter = edge.enter, leave = edge.leave }
	end

	return bands, edges
end

--[[
    Sets the crowd cap every turn reads from the next run on, in process
    and on every worker alike, nil for none, refused as the server's check
    refuses tiers.crowd, for a dev run that compares a server with the cap
    and without it
--]]

function Relay.setCrowd(crowd: Crowd?)
	if not Started then
		error("Relay.setCrowd ran before Relay.start", 2)
	end

	if crowd ~= nil then
		Config.crowd(crowd)
	end

	tuneCrowd(crowd)
end

-- The crowd cap every turn reads, as tiers or Relay.setCrowd last gave it, in a new table, nil for none
function Relay.crowd(): Crowd?
	local crowd: Crowd? = Bands.crowd
	if crowd == nil then
		return nil
	end

	return { size = crowd.size, rate = crowd.rate, floor = crowd.floor }
end

-- Starts the far rate under load's count of runs in a row afresh, with the farthest band as given, and counts the
-- seam's call, so a round out at the call is neither measured nor judged
local function recount()
	Caps.sets += 1
	Caps.overs = 0
	Caps.unders = 0
	Caps.lowered = false
	lowerFar()
end

--[[
    Sets relay.budget from the next run on, the seconds of its own work on
    the server's thread a run may take before the viewers left wait for
    the next, or turns it off with nil. Refused unless a finite number of 0
    or more, and nil refused while the far rate under load is set, as the
    server's check refuses tiers.underLoad without relay.budget. A round
    out at the call still leaves the viewers its run left, but is neither
    measured nor judged. The next run hands every worker turn in, unless
    the budget is 0, which every run reaches, and the far rate under load
    counts afresh
--]]

function Relay.setBudget(seconds: number?)
	if not Started then
		error("Relay.setBudget ran before Relay.start", 2)
	elseif seconds ~= nil and (type(seconds) ~= "number" or not (seconds >= 0 and seconds < math.huge)) then
		error(`Relay.setBudget takes seconds as a finite number of 0 or more, or nil for none, not {seconds}`, 2)
	elseif seconds == nil and Caps.underLoad ~= nil then
		error("Relay.setBudget takes nil only once Relay.setUnderLoad(nil) has turned the far rate under load off", 2)
	end

	-- Every run reaches a budget of 0, the next one among them
	Caps.budget = seconds
	Caps.hand = seconds == 0 and 0 or nil
	recount()
end

-- The seconds relay.budget is set to, nil while it is off
function Relay.budget(): number?
	return Caps.budget
end

--[[
    Sets the far rate under load from the next run on, the relay runs in a
    row over relay.budget that lower the farthest band and in a row under
    it that put it back and what its aim and floor are multiplied by, or
    turns it off with nil, refused as the server's check refuses
    tiers.underLoad, and with no relay budget set. Its count of runs in a
    row starts afresh, with the farthest band as given, and a round out at
    the call is neither measured nor judged
--]]

function Relay.setUnderLoad(underLoad: UnderLoad?)
	if not Started then
		error("Relay.setUnderLoad ran before Relay.start", 2)
	end

	if underLoad ~= nil then
		if Caps.budget == nil then
			error("Relay.setUnderLoad takes the far rate under load only once Relay.setBudget has set a budget", 2)
		end

		Config.underLoad(underLoad)
		Caps.underLoad = { runs = underLoad.runs, scale = underLoad.scale }
	else
		Caps.underLoad = nil
	end

	recount()
end

-- The far rate under load as Relay.setUnderLoad last set it, in a new table, nil while it is off
function Relay.underLoad(): UnderLoad?
	local underLoad: UnderLoad? = Caps.underLoad
	if underLoad == nil then
		return nil
	end

	return { runs = underLoad.runs, scale = underLoad.scale }
end

--[[
    Sets a slot's look, the game's slot-table fields, for its current
    life. Each viewer currently sent it gets the change on its next flush,
    and one not sent it gets it with its next reveal
--]]

function Relay.setLook(slot: number, look: Values)
	if not Started then
		error("Relay.setLook ran before Relay.start", 2)
	end

	checkSlot(slot, "setLook")
	if type(look) ~= "table" then
		error(`Relay.setLook takes the look's fields in a table, not a {typeof(look)}`, 2)
	end

	local length: number = Fields.write(Layout.slot, look, LookScratch, 0)
	local generation: number = Slots.get(slot)

	-- The change is handed to the taps while the life's look before it is still there, empty for none
	if Taps.reliable then
		local previous: number = 0
		if buffer.readu8(LookLives, slot) == generation + 1 then
			previous = buffer.readu8(LookLengths, slot)
		end

		Taps.look(slot, slice(Looks, slot * MAX_LOOK, previous), slice(LookScratch, 0, length))
	end

	buffer.copy(Looks, slot * MAX_LOOK, LookScratch, 0, length)
	buffer.writeu8(LookLengths, slot, length)
	buffer.writeu8(LookLives, slot, generation + 1)
	buffer.writeu16(LookVersions, slot * 2, (buffer.readu16(LookVersions, slot * 2) + 1) % WRAP)
	mark(slot)
end

--[[
    Puts a slot's current life in Invisible mode or takes it out: while on,
    no other viewer is sent it, teammates included, so each one sent it gets
    a hide on its next run and nothing hears its steps
--]]

function Relay.setInvisible(slot: number, on: boolean)
	checkSlot(slot, "setInvisible")
	if type(on) ~= "boolean" then
		error(`Relay.setInvisible takes true or false, not {on}`, 2)
	end

	-- A run that left a viewer has its footsteps carried by the next, which judges them by that run's own marks
	if Caps.left > 0 then
		Turn.hush()
	end

	if on then
		local generation: number = Slots.get(slot)
		buffer.writeu8(Invisible, slot, generation + 1)
	else
		buffer.writeu8(Invisible, slot, 0)
	end

	mark(slot)
end

--[[
    A shooter's bullet passed near a viewer, so the shooter's record goes
    to it at no less than shotNear.rate for shotNear.seconds and weighs
    twice in its queue, while the viewer is sent the shooter
--]]

function Relay.shotNear(key: Key, slot: number)
	checkSlot(slot, "shotNear")

	local through: number = RunTick + ShotTicks
	if Out then
		defer(Wire.SHOT_NEAR, key, slot, through)
	else
		shotNearNow(key, slot, through)
	end
end

--[[
    Gives every viewer currently sent a slot a fresh pending reveal of it,
    with its record and its look in the same block, and no other viewer
    anything, as a sleeper's move needs
--]]

function Relay.reveal(slot: number)
	checkSlot(slot, "reveal")

	local generation: number = Slots.get(slot)
	if Out then
		defer(Wire.REVEAL, nil, slot, generation)
	else
		revealNow(slot, generation)
	end
end

--[[
    Makes every character a viewer is currently sent a pending reveal again,
    with its look and held item in the same block, and its own character's
    look entry too, as a spectate's start and switch need of the target's
    view and its end of the moderator's own. Its records go whole until a
    block from the next run on is acknowledged
--]]

function Relay.revealAll(key: Key)
	local floor: number = Run + 1
	if Out then
		defer(Wire.REVEAL_ALL, key, 0, floor)
	else
		revealAllNow(key, floor)
	end
end

--[[
    Whether a viewer is currently sent a slot's current life: from the tick
    its reveal was first carried until the tick its hide is, as of the run
    before while a round is out
--]]

function Relay.isSent(key: Key, slot: number): boolean
	checkSlot(slot, "isSent")

	local view: Seen? = viewFor(key)
	if not view then
		return false
	end

	local generation: number = Slots.get(slot)

	return sentTo(key, view, slot, generation)
end

--[[
    The viewers currently sent a slot's current life, in a list of their
    own, for a cue the game sends only to the screens that show it, as of
    the run before while a round is out
--]]

function Relay.viewersOf(slot: number): { Key }
	checkSlot(slot, "viewersOf")

	local generation: number = Slots.get(slot)
	local keys: { Key } = {}

	for key: Key, home: number in Homes do
		local view: Seen? = viewAt(key, home)
		if view and sentTo(key, view, slot, generation) then
			table.insert(keys, key)
		end
	end

	return keys
end

-- What a slot wears for a keyframe, each in a new buffer: its look when it is set for the life, and its held item
local function worn(slot: number, generation: number, facts: Facts): (buffer, buffer)
	local look: buffer = buffer.create(0)
	if buffer.readu8(LookLives, slot) == generation + 1 then
		look = slice(Looks, slot * MAX_LOOK, buffer.readu8(LookLengths, slot))
	end

	return look, slice(facts.helds, slot * MAX_HELD, buffer.readu8(facts.heldLengths, slot))
end

-- A slot's character for a keyframe: its kind, newest record, look and held item
local function keyed(
	slot: number,
	kind: Block.Kind,
	withheld: boolean,
	generation: number,
	facts: Facts
): Keyframe.Character
	local look: buffer, held: buffer = worn(slot, generation, facts)

	return {
		kind = kind,
		withheld = withheld,
		record = slice(facts.records, slot * RECORD_BYTES, RECORD_BYTES),
		look = look,
		held = held,
	}
end

-- A view's own character for a keyframe, as its last turn claimed it, or nil while it claimed none
local function ownOf(view: Seen, facts: Facts): Keyframe.Own?
	local slot: number? = view.own
	if slot == nil or not bit32.btest(buffer.readu16(view.flags, slot * 2), OWN) then
		return nil
	end

	local generation: number = buffer.readu8(view.generations, slot)
	local look: buffer, held: buffer = worn(slot, generation, facts)

	return { id = Record.id(slot, generation), look = look, held = held }
end

--[[
    A viewer's current view as one buffer a clip ring starts from: each
    character its client is sent with its kind, newest record, look and
    held item, the called platforms the server handle passes in, the
    gravity in force, the shared table's when none is given, and its own
    character with its look and held item. A moderator watching a target is
    sent the target's view, so its keyframe holds the target's characters,
    its own character and, marked withheld, those withheld from the target,
    with their looks. While a round is out, a worker's view is as of the run
    before
--]]

function Relay.keyframe(key: Key, platforms: { Keyframe.Platform }?, gravity: number?): buffer
	local characters: { Keyframe.Character } = {}
	local view: Seen? = viewFor(key)
	local sequence: number = 0
	local own: Keyframe.Own? = nil

	local facts: Facts = Live
	if Out then
		facts = Frozen
	end

	if view then
		sequence = Heard[key] or 0

		local source: Seen = view
		local sourceKey: Key = key
		local watching: Key? = Watching[key]
		if watching ~= nil then
			local watched: Seen? = viewFor(watching)
			if watched then
				source = watched
				sourceKey = watching
			end
		end

		-- An in-process view took this run's turn at the dispatch, so it goes with the world this run left
		if Out and Homes[sourceKey] == 0 then
			facts = Live
		end

		own = ownOf(source, facts)

		local revealed: { [number]: number }? = Revealed[sourceKey]
		for _, slot: number in source.tracked do
			if bit32.btest(buffer.readu16(source.flags, slot * 2), SENT) then
				local code: number = buffer.readu8(source.kinds, slot)
				local given: number? = revealed and revealed[slot]
				if given ~= nil then
					code = given
				end

				local kind: Block.Kind = Block.KINDS[code + 1]
				table.insert(characters, keyed(slot, kind, false, buffer.readu8(source.generations, slot), facts))
			end
		end

		-- The withheld set as the target's last turn left it, players alone
		local withheld: { read flags: buffer, read lives: buffer }? = source.withheld
		if source ~= view and withheld then
			for _, slot: number in source.tracked do
				local life: number = buffer.readu8(withheld.lives, slot)
				if
					bit32.btest(buffer.readu8(withheld.flags, slot), WITHHELD)
					and life == buffer.readu8(facts.generations, slot)
				then
					table.insert(characters, keyed(slot, "Player", true, life, facts))
				end
			end
		end
	end

	return Keyframe.write({
		hash = Keyed.hash,
		tick = facts.tick,
		sequence = sequence,
		characters = characters,
		platforms = platforms or {},
		gravity = gravity or Keyed.gravity,
		own = own,
	})
end

--[[
    What a slot wears, each in a new buffer: its look for its current life,
    empty while none is set, and its held item as the last relay run packed
    it, empty while nothing is held
--]]

function Relay.wearing(slot: number): (buffer, buffer)
	checkSlot(slot, "wearing")

	local generation: number = Slots.get(slot)
	local look: number = 0
	if buffer.readu8(LookLives, slot) == generation + 1 then
		look = buffer.readu8(LookLengths, slot)
	end

	return slice(Looks, slot * MAX_LOOK, look), slice(Helds, slot * MAX_HELD, buffer.readu8(HeldLengths, slot))
end

--[[
    Keeps the render distance a viewer's client sent, in studs, held to
    relevancy.leave, which its relevancy reaches from its next turn until
    it sends another or leaves
--]]

function Relay.setDistance(key: Key, distance: number)
	if not Started then
		error("Relay.setDistance ran before Relay.start", 2)
	elseif type(distance) ~= "number" or not (distance > 0) then
		error(`Relay.setDistance takes a render distance in studs above 0, not {distance}`, 2)
	end

	if Out then
		defer(Wire.SET_DISTANCE, key, 0, distance)
	else
		setDistanceNow(key, distance)
	end
end

--[[
    Forgets a viewer that left, with everything pending for it
--]]

function Relay.remove(key: Key)
	if Out then
		defer(Wire.REMOVE, key, 0, 0)
	else
		removeNow(key)
	end
end

--[[
    The running totals since start of the records the band ticks placed in
    a viewer's blocks, of those the viewer's room left out, of the bodies
    the viewers' turns gathered to measure, and of the candidates the turns
    held outside their viewer's crowd cap, in process and on the workers, as
    of the last round brought in
--]]

function Relay.counts(): (number, number, number, number)
	local sent: number, cut: number, visited: number, rest: number = Turn.counts()

	return sent + Totals.sent, cut + Totals.cut, visited + Totals.visited, rest + Totals.rest
end

--[[
    The frame caps' running totals since start: the viewer turns
    relay.budget left, the runs judged over it, and the runs taken with the
    far rate under load holding the farthest band lowered
--]]

function Relay.caps(): (number, number, number)
	return Caps.totalLeft, Caps.totalOver, Caps.halved
end

--[[
    With relay.clocks on, each section's ring of the runs before the one
    running, by the section's name, as CLOCKS lists them; empty while the
    clocks are off. The rings are the relay's own, which each run rewrites
--]]

function Relay.clocks(): { [string]: ClockRing }
	return Clock.rings
end

--[[
    Adds a time the server handle measured to a section of the running
    run's clocks, in seconds: flushTick, the relay stage's flush, and
    flushFinish, its finish's. Errors on a name that is no section
--]]

function Relay.clocked(name: string, seconds: number)
	local at: number? = CLOCK_AT[name]
	if at == nil then
		error(`Relay.clocked takes one of the relay's clock sections, not {name}`, 2)
	end

	add(at, seconds)
end

return Relay
