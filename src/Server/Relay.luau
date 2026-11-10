--[[
    The relay: which characters each viewer is sent and how often inside its
    budget, its blocks of records, footsteps and pending entries, copied to
    each moderator watching it, and the withheld block those moderators get
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
local Record = require(script.Parent.Parent.Codec.Record)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.Parent.Codec.StateWord)
local Taps = require(script.Parent.Taps)

local SLOTS: number = Constants.SLOTS
local RECORD_BYTES: number = Constants.RECORD_BYTES
local BLOCK_BYTES: number = Constants.MAX_RELAY_BYTES
local HEADER_BYTES: number = Constants.RELAY_HEADER_BYTES
local REVEAL_BYTES: number = Constants.REVEAL_BYTES
local HIDE_BYTES: number = Constants.HIDE_BYTES
local LOOK_ENTRY_BYTES: number = Constants.LOOK_ENTRY_BYTES
local FOOTSTEP_BYTES: number = Constants.FOOTSTEP_BYTES
local PREFIX_BYTES: number = Constants.PREFIX_BYTES
local MAX_LOOK: number = Constants.MAX_LOOK
local MAX_HELD: number = Constants.MAX_HELD
local MAX_RECORDS: number = Constants.MAX_RELAY_RECORDS
local MASK_BITS: number = Constants.ACK_MASK_BITS
local COUNTERS: number = 2 ^ Constants.COUNTER_BITS -- The values a state word's jump or land counter wraps through
local WRAP: number = 2 ^ 16 -- The values a u16 wire number wraps through
local SEQUENCES: number = WRAP - Constants.FIRST_SEQUENCE -- A viewer's sequences run 1 to 65,535, so 0 still means none
local SECTION_LIMIT: number = 2 ^ 8 - 1 -- The most entries a block's u8 counts hold
local FRAME_BYTES: number = 3 -- Volt's event id and the buffer's u16 length in front of each block it sends
local BYTES_PER_KB: number = 1000 -- A budget's KB, as the design counts them
local TURN: number = 360 -- Degrees
local QUARTER_TURN: number = TURN / 4 -- The degrees a record's pitch steps reach either way

-- A target's record goes on each of this many tier ticks after it stops changing, then once every STILL_SECONDS
-- while it stays still, so a lost last update freezes a pose for at most that long
local REST_REPEATS: number = 3
local STILL_SECONDS: number = 1
local TURN_CHANGE: number = 0.5 -- Degrees a yaw or pitch moves by before the move alone counts as a change
local YAW_CHANGE: number = Constants.ANGLE_STEPS * TURN_CHANGE / TURN -- That move in a record's yaw steps
local PITCH_CHANGE: number = Constants.RECORD_PITCH_STEPS * TURN_CHANGE / QUARTER_TURN -- And in its pitch steps

-- What a viewer's acknowledgment can clear: the blocks it can still name and the pending entries they carried, each
-- logged as its slot times ENTRY_PARTS plus its part
local RING: number = 64
local LOG: number = 4096
local ENTRY_PARTS: number = 5
local VISIBILITY: number = 0 -- A reveal or a hide
local LOOK_PART: number = 1
local HELD_PART: number = 2
local WITHHELD_LOOK_PART: number = 3 -- A withheld character's look, which rides the withheld block beside the copy
local WITHHELD_HELD_PART: number = 4

-- Each block keeps the recipients still to acknowledge it as a mask, a bit each: SELF its own viewer, and each
-- moderator watching that viewer the bit it was given, 1 to MAX_WATCHERS
-- Whiteoak TODO: the mask is a u32, so one target takes at most 31 watchers; more needs a wider mask per block, two
-- u32s or a buffer of bits a block, once a game puts more than 31 moderators on one target
local SELF: number = 2 ^ 0
local MAX_WATCHERS: number = Constants.MAX_WATCHERS

local STEP_START: number = 256 -- The steps one run holds before its buffers grow
local SILENT: number = -1 -- A squared range no step falls inside, for a kind the game gives no range

local UNSTARTED: string = "The relay sends nothing until Relay.start hands it its settings and its four functions"

-- What a sent target's tier tick lists its record as
local UNLISTED: number = 0
local OWED: number = 1 -- At or past its floor
local QUEUED: number = 2 -- Under its floor, waiting in the queue by its priority

-- What a viewer holds for a slot, a bit each
local RELEVANT: number = 2 ^ 0 -- Inside its relevancy for the slot's kind
local NEAR: number = 2 ^ 1 -- Inside the near tier
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

-- A footstep's kinds by code from 1, each heard to the range keyed by its name in lower case
local STEPS: { Block.Step } = { "Walk", "Sprint", "Jump", "Land" }
local WALK: number = 1
local SPRINT: number = 2
local JUMP: number = 3
local LAND: number = 4

type Command = State.Command
type Layout = Fields.Layout
type Limits = Command.Limits
type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type State = State.State
type Values = State.Values

type Bot = { Name: string }
type Key = Player | Bot
type Platforms = { [number]: vector } -- Each platform's place at the tick, by its id

-- What the server handle starts the relay with: the game's checked tables and its compiled declarations
export type Settings = {
	shared: Shared,
	server: ServerSettings,
	layout: Layout,
}

-- One viewer as the server handle hands it in each relay tick, a table it keeps and refills
export type Viewer = {
	key: Key, -- The player or bot, which the relay keeps its view under and hands send and traffic
	slot: number?, -- Its own character's slot, nil while it has none
	position: vector, -- Where its relevancy, tiers and earshot are measured from
	acknowledged: number, -- The newest relay sequence its client received, 0 for none
	received: number, -- The mask of the 16 sequences before that one, bit 0 the one just before
	target: Key?, -- The viewer it spectates, whose blocks it gets copies of in place of its own; nil for none
}

-- What a watched target's withheld block keeps for each slot, by slot in buffers
type Withheld = {
	flags: buffer, -- u8
	lives: buffer, -- u8: the generation its withheld stretch belongs to
	lookSent: buffer, -- u16: the look version the watchers were last given
	heldSent: buffer,
	lookFrom: buffer, -- u16: the copy the pending look first rode beside since it last changed
	heldFrom: buffer,
	aim: buffer, -- f32: the tier ticks it is owed at the target's aim rate
}

-- What the relay keeps for one viewer: the slots it holds anything for, each field a buffer by slot, the blocks
-- its acknowledgment can still name with the pending entries each carried, and the moderators watching it
type View = {
	key: Key,
	distance: number, -- Its client's render distance held to relevancy.leave, which is what it has until one comes
	sequence: number, -- The message sequence its next block takes
	newest: number, -- The sequence of the last block it was sent, 0 before the first
	heard: number, -- The sequence of the newest block its client was sent, its own or a copy, 0 before the first
	watching: Key?, -- The target it last watched, nil while its own view runs
	turn: number, -- The last run it was handed in with no target, so its own view ran
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
	lastRecord: buffer, -- u32: the run its last record went in, 0 for none
	shotUntil: buffer, -- u32: the last run a shot near it raises that shooter's rate
	aim: buffer, -- f32: the tier ticks it is owed at the target's aim rate
	floor: buffer, -- f32: and at its floor rate
	ringSequences: buffer, -- u32: each remembered block's sequence plus 1, 0 for none
	ringStarts: buffer, -- f64: where its entries start in the log
	ringCounts: buffer, -- u16: how many it carried
	ringOwed: buffer, -- u32: the mask of its recipients still to acknowledge it
	log: buffer, -- u16 a pending entry
	logHead: number, -- The entries ever logged
	watchers: { [number]: Key }, -- The moderators watching it, by their bit
	watcherViews: { [number]: View },
	bits: { [Key]: number },
	watcherRuns: buffer, -- u32: the last run each bit's watcher was handed in watching it
	watcherCount: number,
	withheld: Withheld?, -- Its withheld block's state, made the first time it is watched
}

-- What start hands in, each refusing until then
local Started: boolean = false

local Send: (keys: { Key }, data: buffer) -> () = function (_: { Key }, _: buffer)
	error(UNSTARTED)
end

local SendWithheld: (keys: { Key }, data: buffer) -> () = function (_: { Key }, _: buffer)
	error(UNSTARTED)
end

local Traffic: (key: Key) -> number = function (_: Key): number
	error(UNSTARTED)
end

local IsHidden: (viewer: Viewer, slot: number) -> boolean = function (_: Viewer, _: number): boolean
	error(UNSTARTED)
end

local Layout: Layout = Fields.compile({ command = {}, rules = {}, server = {}, slot = {}, held = {} })
local DeclarationsHash: number = 0
local Limits: Limits = { lean = 0, headCone = 0 }

-- The game's settings as the relay reads them, each distance squared and each budget in bytes a second, but the
-- radii each viewer's own render distance caps, in studs, which share one table since Luau caps a chunk's locals
local RelayRate: number = 0
local StillRuns: number = 0
local Radii: { enter: number, leave: number, sleepers: number, npcs: number } =
	{ enter = 0, leave = 0, sleepers = 0, npcs = 0 }
local NearEnterSquared: number = 0
local NearLeaveSquared: number = 0
local NearAim: number = 0
local NearFloor: number = 0
local FarAim: number = 0
local FarFloor: number = 0
local WeightNear: number = 0
local WeightFar: number = 0
local WeightShooter: number = 0
local WeightCone: number = 0
local ShotRate: number = 0
local ShotRuns: number = 0
local Soft: number = 0
local Hard: number = 0
local NpcNearSquared: number = 0
local NpcFarRate: number = 0
local StrideWalk: number = 0
local StrideSprint: number = 0
local Heard: { number } = { SILENT, SILENT, SILENT, SILENT } -- Each footstep kind's squared range

-- The radii of the viewer whose turn it is, squared, from its render distance, found once a turn
local EnterSquared: number = 0
local LeaveSquared: number = 0
local SleeperSquared: number = 0
local NpcRangeSquared: number = 0

local Run: number = 0 -- The relay runs so far, which every timing counts in
local TickWire: number = 0 -- The relay tick this run's blocks carry, a u16
local RecordsSent: number = 0 -- The records the tier ticks' lists placed in a block, since start
local RecordsCut: number = 0 -- And those a viewer's room left out

-- Each slot this run, by slot: whether it is present, its life, its kind and its encoded record
local Present: buffer = buffer.create(SLOTS * 4) -- u32: the last run it was handed in with an entry
local Generations: buffer = buffer.create(SLOTS)
local Kinds: buffer = buffer.create(SLOTS)
local Records: buffer = buffer.create(SLOTS * RECORD_BYTES)
local References: buffer = buffer.create(SLOTS * RECORD_BYTES) -- The record each change is measured from
local Changed: buffer = buffer.create(SLOTS * 4) -- u32: the run its record last changed

-- Each slot's look and held item, packed, with a version that moves on each change
local Looks: buffer = buffer.create(SLOTS * MAX_LOOK)
local LookLengths: buffer = buffer.create(SLOTS)
local LookVersions: buffer = buffer.create(SLOTS * 2)
local LookLives: buffer = buffer.create(SLOTS) -- The generation plus 1 its look was set for, 0 for none
local Helds: buffer = buffer.create(SLOTS * MAX_HELD)
local HeldLengths: buffer = buffer.create(SLOTS) -- 0 while nothing is held
local HeldVersions: buffer = buffer.create(SLOTS * 2)
local Invisible: buffer = buffer.create(SLOTS) -- The generation plus 1 it is invisible for, 0 for none

-- Each slot's last sample for its footsteps: where it stood, and what its steps since its last step have covered
local Previous: { vector } = table.create(SLOTS, vector.zero)
local PreviousMaterials: { Enum.Material } = table.create(SLOTS, Enum.Material.Air) -- The ground it last stood on
local Sampled: buffer = buffer.create(SLOTS * 4) -- u32: the run it was sampled at, 0 for never
local PreviousLives: buffer = buffer.create(SLOTS)
local PreviousEpochs: buffer = buffer.create(SLOTS)
local PreviousJumps: buffer = buffer.create(SLOTS)
local PreviousLands: buffer = buffer.create(SLOTS)
local Stepping: buffer = buffer.create(SLOTS) -- 1 when it stood in a gait that steps
local Walked: buffer = buffer.create(SLOTS * 8) -- f64: studs since its last step

-- This run's footsteps: whose each is, its kind, where it fell, and its entry, encoded once for every viewer
local StepCapacity: number = STEP_START
local StepCount: number = 0
local StepSlots: buffer = buffer.create(STEP_START * 2)
local StepKinds: buffer = buffer.create(STEP_START)
local StepPlaces: { vector } = {}
local StepData: buffer = buffer.create(STEP_START * FOOTSTEP_BYTES)

-- The block being filled for the viewer whose turn it is, and what its tick may still take
local Out: Block.Block = Block.new()
local Open: boolean = false
local Filled: number = 0 -- The open block's bytes
local Spent: number = 0 -- The viewer's bytes this tick, framing included
local HardRoom: number = 0 -- The bytes it may take this tick for what is owed, and for the rest
local SoftRoom: number = 0

-- Whiteoak TODO: Volt sends a buffer field whole, so each block goes in a buffer of its exact length, kept here
-- once per length and reused, at most 889 buffers and Volt's copy of each block; a buffer field that takes a length
-- would remove both, a Volt task if G3 shows the cost
local Outgoing: { [number]: buffer } = {}

-- Who the open block goes to: the viewer whose turn it is, then each moderator watching it, with their views and
-- the mask of their bits, and the moderators alone, whom its withheld block goes to
local Recipients: { Key } = {}
local RecipientViews: { View } = {}
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

-- The viewer's turn's lists, kept across turns
local Hides: { number } = {}
local Reveals: { number } = {}
local Restyles: { number } = {}
local Floors: { number } = {}
local Fills: { number } = {}
local Priorities: buffer = buffer.create(SLOTS * 8) -- f64: each listed record's place in the queue, highest first

local Scratch: Record.Record = Record.new()
local Footstep: Block.Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
local LookScratch: buffer = buffer.create(MAX_LOOK)
local HeldScratch: buffer = buffer.create(MAX_HELD)

local Views: { [Key]: View } = {}

local Relay = {}

-- The squared range a footstep kind is heard to, or SILENT for a kind the game gives none
local function heard(range: number?): number
	if range == nil then
		return SILENT
	end

	return range * range
end

--[[
    Starts the relay with the game's tables and what it sends through: send
    fires one block to a viewer and the moderators watching it, and
    sendWithheld one withheld block to those moderators, each in one
    fireList over the relay's own list, valid during the call; traffic is
    Volt's count of the bytes sent to a viewer over the last second, and
    isHidden is anti-ESP's answer for a pair. It runs once
--]]

function Relay.start(
	settings: Settings,
	send: (keys: { Key }, data: buffer) -> (),
	sendWithheld: (keys: { Key }, data: buffer) -> (),
	traffic: (key: Key) -> number,
	isHidden: (viewer: Viewer, slot: number) -> boolean
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
	end

	local shared: Shared = settings.shared
	local server: ServerSettings = settings.server

	Started = true
	Send = send
	SendWithheld = sendWithheld
	Traffic = traffic
	IsHidden = isHidden
	Layout = settings.layout
	DeclarationsHash = Fields.hash(settings.layout)
	Limits = { lean = shared.step.lean, headCone = shared.step.headCone }

	RelayRate = shared.rates.relay
	StillRuns = STILL_SECONDS * RelayRate
	Radii = {
		enter = server.relevancy.enter,
		leave = server.relevancy.leave,
		sleepers = server.sleepers.radius,
		npcs = server.npcs.range,
	}
	NearEnterSquared = server.tiers.nearEnter ^ 2
	NearLeaveSquared = server.tiers.nearLeave ^ 2
	NearAim = server.tiers.nearAim
	NearFloor = server.tiers.nearFloor
	FarAim = server.tiers.farAim
	FarFloor = server.tiers.farFloor
	WeightNear = server.weights.near
	WeightFar = server.weights.far
	WeightShooter = server.weights.shooter
	WeightCone = server.weights.cone
	ShotRate = server.shotNear.rate
	ShotRuns = math.ceil(server.shotNear.seconds * RelayRate)
	Soft = server.budget.soft * BYTES_PER_KB
	Hard = server.budget.hard * BYTES_PER_KB
	NpcNearSquared = server.npcs.near ^ 2
	NpcFarRate = server.npcs.farRate
	StrideWalk = server.footsteps.stride.walk
	StrideSprint = server.footsteps.stride.sprint

	for code: number, step: Block.Step in STEPS do
		Heard[code] = heard(server.footsteps.range[string.lower(step)])
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
    that platform stands this tick, and in world coordinates otherwise
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

	if changed(at) then
		buffer.copy(References, at, Records, at, RECORD_BYTES)
		buffer.writeu32(Changed, slot * 4, Run)
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
    the bytes differ from the last run's. An empty table holds nothing,
    which travels as a held part of length 0
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
end

-- Doubles the run's footstep buffers, keeping the steps already in them
local function grow()
	local capacity: number = StepCapacity * 2
	local slots: buffer = buffer.create(capacity * 2)
	local kinds: buffer = buffer.create(capacity)
	local data: buffer = buffer.create(capacity * FOOTSTEP_BYTES)

	buffer.copy(slots, 0, StepSlots)
	buffer.copy(kinds, 0, StepKinds)
	buffer.copy(data, 0, StepData)

	StepCapacity = capacity
	StepSlots = slots
	StepKinds = kinds
	StepData = data
end

-- Encodes one footstep of a slot's, unless the game gives its kind no range
local function emit(slot: number, kind: number, at: vector, material: Enum.Material)
	if Heard[kind] == SILENT then
		return
	end

	if StepCount == StepCapacity then
		grow()
	end

	local index: number = StepCount
	StepCount += 1

	buffer.writeu16(StepSlots, index * 2, slot)
	buffer.writeu8(StepKinds, index, kind)
	StepPlaces[index + 1] = at

	Footstep.at = at
	Footstep.kind = STEPS[kind]
	Footstep.material = material
	Block.writeFootstep(Footstep, StepData, index * FOOTSTEP_BYTES)
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
	local index: number = slot + 1
	local position: vector = state.position
	local previous: vector = Previous[index]
	local sampled: number = buffer.readu32(Sampled, slot * 4)

	-- Only a sample from the run before, of the same life and epoch, makes a stretch of ground covered
	local followed: boolean = sampled ~= 0 and sampled == Run - 1 and buffer.readu8(PreviousLives, slot) == generation
	if followed and buffer.readu8(PreviousEpochs, slot) == state.epoch then
		local jumps: number = (state.jumps - buffer.readu8(PreviousJumps, slot)) % COUNTERS
		for _ = 1, jumps do
			emit(slot, JUMP, previous, PreviousMaterials[index])
		end

		local lands: number = (state.lands - buffer.readu8(PreviousLands, slot)) % COUNTERS
		for _ = 1, lands do
			emit(slot, LAND, position, state.groundMaterial)
		end

		if stepping(state) and buffer.readu8(Stepping, slot) == 1 then
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
				local along: number = math.max(stride - buffer.readf64(Walked, slot * 8), 0)

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

				buffer.writef64(Walked, slot * 8, length - (along - stride))
			end
		end
	end

	Previous[index] = position
	buffer.writeu32(Sampled, slot * 4, Run)
	buffer.writeu8(PreviousLives, slot, generation)
	buffer.writeu8(PreviousEpochs, slot, state.epoch)
	buffer.writeu8(PreviousJumps, slot, state.jumps)
	buffer.writeu8(PreviousLands, slot, state.lands)

	if stepping(state) then
		buffer.writeu8(Stepping, slot, 1)
	else
		buffer.writeu8(Stepping, slot, 0)
	end

	if state.grounded then
		PreviousMaterials[index] = state.groundMaterial
	end
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

	return lookAgain(view, slot, bit32.bor(bit32.band(flags, bit32.bnot(HIDE + VISIBILITY_CARRIED)), REVEAL))
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

-- A pair's relevancy and tier from its squared distance by the target's kind, a player's and a body's entering at
-- the inner radius and leaving past the outer
local function measure(flags: number, kind: number, squared: number): number
	local relevant: boolean
	local near: boolean = false

	if kind == NPC then
		relevant = squared <= NpcRangeSquared
		near = squared <= NpcNearSquared
	elseif kind == SLEEPER then
		relevant = squared <= SleeperSquared
	else
		if bit32.btest(flags, RELEVANT) then
			relevant = squared <= LeaveSquared
		else
			relevant = squared <= EnterSquared
		end

		if bit32.btest(flags, NEAR) then
			near = squared <= NearLeaveSquared
		else
			near = squared < NearEnterSquared
		end
	end

	flags = bit32.band(flags, bit32.bnot(RELEVANT + NEAR))

	if relevant then
		flags = bit32.bor(flags, RELEVANT)

		if near then
			flags = bit32.bor(flags, NEAR)
		end
	end

	return flags
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

-- Clears what one remembered block carried, once every recipient it went to has acknowledged it
local function discharge(view: View, ring: number)
	local sequence: number = buffer.readu32(view.ringSequences, ring * 4) - 1
	buffer.writeu32(view.ringSequences, ring * 4, 0)

	-- Entries the log has since written over ride on until a later block's acknowledgment clears them
	local start: number = buffer.readf64(view.ringStarts, ring * 8)
	if view.logHead - start > LOG then
		return
	end

	for index: number = start, start + buffer.readu16(view.ringCounts, ring * 2) - 1 do
		local code: number = buffer.readu16(view.log, (index % LOG) * 2)
		clear(view, code // ENTRY_PARTS, code % ENTRY_PARTS, sequence)
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

	for back: number = 1, MASK_BITS do
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
	Out.footstepData = StepData
	Out.recordData = Records

	buffer.writeu32(view.ringSequences, ring * 4, sequence + 1)
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

-- Writes the open block into the buffer of its exact length and sends it to its viewer and every watcher at once
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

	if Taps.observing then
		Taps.relayed(Recipients, RecipientCount, Out, data)
	end

	for index: number = 1, RecipientCount do
		RecipientViews[index].heard = Out.sequence
	end
end

--[[
    Makes room for an entry of bytes in a section holding count entries:
    in the open block, or a fresh one when it would pass 896 B or its count,
    so long as the viewer's tick stays inside room. False leaves both as
    they were
--]]

local function fits(view: View, bytes: number, count: number, room: number): boolean
	local fresh: boolean = not Open or Filled + bytes > BLOCK_BYTES or count >= SECTION_LIMIT
	local cost: number = bytes
	if fresh then
		cost += HEADER_BYTES + FRAME_BYTES
	end

	if Spent + cost > room then
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
	local bytes: number = LOOK_ENTRY_BYTES

	if look then
		bytes += PREFIX_BYTES + buffer.readu8(LookLengths, slot)
	end

	if held then
		bytes += PREFIX_BYTES + buffer.readu8(HeldLengths, slot)
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

	local made: Block.Hide = { slot = 0, generation = 0 }
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

-- Puts a slot's record into the open block, which has room for it, and times its next one from now
local function writeRecord(view: View, slot: number)
	local count: number = Out.recordCount + 1
	Out.records[count] = slot * RECORD_BYTES
	Out.recordCount = count

	local last: number = buffer.readu32(view.lastRecord, slot * 4)
	if buffer.readu32(Changed, slot * 4) > last then
		buffer.writeu8(view.repeats, slot, REST_REPEATS)
	else
		local repeats: number = buffer.readu8(view.repeats, slot)
		if repeats > 0 then
			buffer.writeu8(view.repeats, slot, repeats - 1)
		end
	end

	buffer.writeu32(view.lastRecord, slot * 4, Run)
	buffer.writef32(view.aim, slot * 4, math.max(buffer.readf32(view.aim, slot * 4) - 1, 0))
	buffer.writef32(view.floor, slot * 4, math.max(buffer.readf32(view.floor, slot * 4) - 1, 0))
end

local function addHide(view: View, slot: number)
	if not fits(view, HIDE_BYTES, Out.hideCount, HardRoom) then
		return
	end

	local count: number = Out.hideCount + 1
	local hide: Block.Hide = hideEntry(count)

	hide.slot = slot
	hide.generation = buffer.readu8(view.generations, slot)
	Out.hideCount = count

	-- The viewer stops being sent the character the tick its hide is first carried
	local flags: number = buffer.readu16(view.flags, slot * 2)
	flags = carry(view, slot, VISIBILITY, flags, VISIBILITY_CARRIED, view.visibilityFrom)
	buffer.writeu16(view.flags, slot * 2, bit32.band(flags, bit32.bnot(SENT)))
end

-- A reveal, its look entry and its record, all in one block or not at all
local function addReveal(view: View, slot: number)
	local flags: number = buffer.readu16(view.flags, slot * 2)
	local dressing: boolean = bit32.btest(flags, LOOK + HELD)

	local bytes: number = REVEAL_BYTES + RECORD_BYTES
	if dressing then
		bytes += lookBytes(slot, flags)
	end

	if not fits(view, bytes, math.max(Out.revealCount, Out.lookCount), HardRoom) then
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

	writeRecord(view, slot)

	-- The viewer is sent the character from the tick its reveal is first carried
	flags = carry(view, slot, VISIBILITY, flags, VISIBILITY_CARRIED, view.visibilityFrom)
	buffer.writeu16(view.flags, slot * 2, bit32.bor(flags, SENT))
end

local function addLook(view: View, slot: number)
	local flags: number = buffer.readu16(view.flags, slot * 2)
	if fits(view, lookBytes(slot, flags), Out.lookCount, HardRoom) then
		buffer.writeu16(view.flags, slot * 2, writeLook(view, slot, flags))
	end
end

local function addFootstep(view: View, offset: number)
	if not fits(view, FOOTSTEP_BYTES, Out.footstepCount, HardRoom) then
		return
	end

	local count: number = Out.footstepCount + 1
	Out.footsteps[count] = offset
	Out.footstepCount = count
end

-- The higher of two listed records' places in the queue
local function ahead(a: number, b: number): boolean
	return buffer.readf64(Priorities, a * 8) > buffer.readf64(Priorities, b * 8)
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
    Places a list's records inside room, highest in the queue first when
    they can't all fit, and stops at the first that doesn't, since every
    record is the same size. Those left keep at most one tier tick owed
--]]

local function placeRecords(view: View, list: { number }, count: number, room: number)
	trim(list, count)

	local blocks: number = count // MAX_RECORDS + 1
	if Spent + count * RECORD_BYTES + blocks * (HEADER_BYTES + FRAME_BYTES) > room then
		table.sort(list, ahead)
	end

	for index: number = 1, count do
		local slot: number = list[index]
		if not fits(view, RECORD_BYTES, 0, room) then
			RecordsCut += count - index + 1
			break
		end

		writeRecord(view, slot)
		RecordsSent += 1
	end

	for index: number = 1, count do
		local slot: number = list[index]
		if buffer.readu32(view.lastRecord, slot * 4) ~= Run then
			buffer.writef32(view.aim, slot * 4, math.min(buffer.readf32(view.aim, slot * 4), 1))
			buffer.writef32(view.floor, slot * 4, math.min(buffer.readf32(view.floor, slot * 4), 1))
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

	local flags: number = bit32.band(buffer.readu16(view.flags, own * 2), bit32.bnot(RELEVANT + NEAR + CULLED))
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

--[[
    Every other present body against the viewer: its relevancy and tier,
    whether anti-ESP hides it, which leaves it culled, and the stretch that
    follows. Invisible bodies are wanted by no one and never culled
--]]

local function consider(view: View, viewer: Viewer, states: { [number]: State }, own: number?)
	local origin: vector = viewer.position

	for slot: number, state: State in states do
		if slot == own or buffer.readu32(Present, slot * 4) ~= Run then
			continue
		end

		local generation: number = buffer.readu8(Generations, slot)
		local offset: vector = state.position - origin
		local flags: number = buffer.readu16(view.flags, slot * 2)

		flags = measure(flags, buffer.readu8(Kinds, slot), vector.dot(offset, offset))
		flags = bit32.band(flags, bit32.bnot(CULLED))

		local wanted: boolean = false
		if bit32.btest(flags, RELEVANT) and buffer.readu8(Invisible, slot) ~= generation + 1 then
			if IsHidden(viewer, slot) then
				flags = bit32.bor(flags, CULLED)
			else
				wanted = true
			end
		end

		-- A new life ends whatever the viewer held of the slot's last one, and its reveal replaces any hide
		if bit32.btest(flags, SENT + REVEAL + HIDE) and buffer.readu8(view.generations, slot) ~= generation then
			flags = bit32.band(flags, bit32.bnot(STRETCH))
		end

		flags = settle(view, slot, flags, wanted, generation)

		if bit32.btest(flags, KEEP) then
			track(view, slot)
		end

		buffer.writeu16(view.flags, slot * 2, flags)
	end
end

--[[
    Lists a sent player's or NPC's record when its tier tick comes and it
    has something to send: a change, a rest repeat or the still repeat. At
    or past its floor it is owed; under it, it waits in the queue by its
    weight times the runs since its last record
--]]

local function schedule(view: View, slot: number, flags: number, offset: vector, facing: vector?): number
	local kind: number = buffer.readu8(Kinds, slot)
	if kind ~= PLAYER and kind ~= NPC then
		return UNLISTED
	end

	local near: boolean = bit32.btest(flags, NEAR)
	local aimRate: number
	local floorRate: number
	local weight: number = WeightFar

	if near then
		weight = WeightNear
	end

	if kind == NPC then
		aimRate = NpcFarRate
		if near then
			aimRate = RelayRate
		end

		floorRate = aimRate
	elseif near then
		aimRate = NearAim
		floorRate = NearFloor
	else
		aimRate = FarAim
		floorRate = FarFloor
	end

	if buffer.readu32(view.shotUntil, slot * 4) >= Run then
		aimRate = math.max(aimRate, ShotRate)
		floorRate = math.max(floorRate, ShotRate)
		weight *= WeightShooter
	end

	if facing and vector.dot(offset, facing) > 0 then
		weight *= WeightCone
	end

	local aim: number = buffer.readf32(view.aim, slot * 4) + math.min(aimRate / RelayRate, 1)
	local floor: number = buffer.readf32(view.floor, slot * 4) + math.min(floorRate / RelayRate, 1)

	if aim < 1 then
		buffer.writef32(view.aim, slot * 4, aim)
		buffer.writef32(view.floor, slot * 4, floor)

		return UNLISTED
	end

	local last: number = buffer.readu32(view.lastRecord, slot * 4)
	local still: boolean = buffer.readu32(Changed, slot * 4) <= last and buffer.readu8(view.repeats, slot) == 0

	-- Its tier tick passes with nothing to send while it stays still
	if still and Run - last < StillRuns then
		buffer.writef32(view.aim, slot * 4, aim - 1)
		buffer.writef32(view.floor, slot * 4, math.max(floor - 1, 0))

		return UNLISTED
	end

	buffer.writef32(view.aim, slot * 4, aim)
	buffer.writef32(view.floor, slot * 4, floor)
	buffer.writef64(Priorities, slot * 8, weight * (Run - last))

	if floor >= 1 then
		return OWED
	end

	return QUEUED
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
	if Taps.observing then
		Taps.withheld(Recipients[1], WithheldOut, data)
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
    anti-ESP never hides one. Each goes at the target's aim rate for its
    tier every tier tick, changed or not, with its look while pending,
    outside the target's budget and to the watchers alone. It carries the
    sequence of the run's last copy, so a look entry clears once the
    acknowledgments of that copy cover it
--]]

local function withhold(view: View, states: { [number]: State })
	local withheld: Withheld? = view.withheld
	if not withheld then
		return
	end

	local records: number, looks: number = 0, 0

	for _, slot: number in view.tracked do
		local flags: number = buffer.readu16(view.flags, slot * 2)
		local state: State? = states[slot]
		local mark: number = buffer.readu8(withheld.flags, slot)

		if
			not state
			or not bit32.btest(flags, CULLED)
			or bit32.btest(flags, SENT)
			or buffer.readu8(Kinds, slot) ~= PLAYER
			or state.moveMode == "Parked"
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

			local rate: number = bit32.btest(flags, NEAR) and NearAim or FarAim
			aim = buffer.readf32(withheld.aim, slot * 4) + math.min(rate / RelayRate, 1)
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
	if looks > 0 and not Copied and fits(view, 0, 0, HardRoom) then
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
		heard = 0,
		watching = nil :: Key?,
		turn = 0,
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
		ringSequences = buffer.create(RING * 4),
		ringStarts = buffer.create(RING * 8),
		ringCounts = buffer.create(RING * 2),
		ringOwed = buffer.create(RING * 4),
		log = buffer.create(LOG * 2),
		logHead = 0,
		watchers = {} :: { [number]: Key },
		watcherViews = {} :: { [number]: View },
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
    MAX_WATCHERS, and sends every withheld character's look again for it
--]]

local function enlist(targetView: View, key: Key, view: View): number?
	for bit: number = 1, MAX_WATCHERS do
		if targetView.watchers[bit] == nil then
			targetView.watchers[bit] = key
			targetView.watcherViews[bit] = view
			targetView.bits[key] = bit
			targetView.watcherCount += 1

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
	view.watcherViews[bit] = nil
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

--[[
    A watcher's run: it is one of its target's recipients, the target's
    blocks numbered past what its client was sent elsewhere when it starts
    watching, and its acknowledgment counts for the target's blocks it was
    sent. False when the target already has all the watchers it takes
--]]

local function watch(viewer: Viewer, target: Key): boolean
	local targetView: View? = targetOf(target)
	if not targetView then
		return true
	end

	local key: Key = viewer.key
	local view: View = viewOf(key)
	local held: number? = targetView.bits[key]
	local bit: number

	if held then
		bit = held
	else
		local given: number? = enlist(targetView, key, view)
		if given == nil then
			return false
		end

		bit = given
	end

	if view.watching ~= target then
		renumber(targetView, view.heard)
		view.watching = target
	end

	buffer.writeu32(targetView.watcherRuns, bit * 4, Run)
	acknowledge(targetView, viewer.acknowledged, viewer.received, 2 ^ bit)

	return true
end

-- The open block's recipients on a viewer's turn: the viewer, then each of its watchers by bit
local function address(view: View)
	Recipients[1] = view.key
	RecipientViews[1] = view
	RecipientCount = 1
	RecipientMask = SELF

	local watchers: number = 0
	if view.watcherCount > 0 then
		for bit: number = 1, MAX_WATCHERS do
			local watcher: Key? = view.watchers[bit]
			if watcher ~= nil then
				RecipientCount += 1
				Recipients[RecipientCount] = watcher
				RecipientViews[RecipientCount] = view.watcherViews[bit]
				RecipientMask += 2 ^ bit
				watchers += 1
				Watchers[watchers] = watcher
			end
		end
	end

	trim(Recipients, RecipientCount)
	trim(RecipientViews, RecipientCount)
	trim(Watchers, watchers)
end

--[[
    One viewer's turn: its acknowledgment, its own character, every body
    against it, then its blocks, each copied to its watchers: pending hides,
    reveals and looks, the footsteps it can hear, the records it is owed
    inside the hard budget and the rest inside the soft budget, and last
    the withheld block, to its watchers alone
--]]

local function turn(viewer: Viewer, states: { [number]: State })
	local key: Key = viewer.key
	local view: View = viewOf(key)

	-- Its own radii: players and bodies enter inside its distance in the server's proportion and leave past it, and
	-- sleepers and NPCs go no farther than it either
	local distance: number = view.distance
	EnterSquared = (distance * Radii.enter / Radii.leave) ^ 2
	LeaveSquared = distance * distance
	SleeperSquared = math.min(Radii.sleepers, distance) ^ 2
	NpcRangeSquared = math.min(Radii.npcs, distance) ^ 2

	-- Back from a spectate, its client may acknowledge the target's blocks a while yet, so its own go on past them
	if view.watching ~= nil then
		renumber(view, view.heard)
		view.watching = nil
	end

	acknowledge(view, viewer.acknowledged, viewer.received, SELF)
	address(view)
	Copied = false

	local own: number? = viewer.slot
	if own ~= nil and not Slots.valid(own) then
		error(`A viewer's slot is one of the slot table's slots, not {own}`)
	end

	claim(view, own)
	consider(view, viewer, states, own)

	-- The viewer's facing, for the view cone, while it has a body
	local origin: vector = viewer.position
	local facing: vector? = nil
	if own ~= nil and buffer.readu32(Present, own * 4) == Run then
		local body: State? = states[own]
		if body then
			facing = vector.create(-Math.sin(body.facing), 0, -Math.cos(body.facing))
		end
	end

	local hides: number, reveals: number, restyles: number, floors: number, fills: number = 0, 0, 0, 0, 0
	local tracked: { number } = view.tracked

	for index: number = #tracked, 1, -1 do
		local slot: number = tracked[index]
		local flags: number = buffer.readu16(view.flags, slot * 2)
		local present: boolean = buffer.readu32(Present, slot * 4) == Run

		if not present and slot ~= own then
			-- A body no longer handed in is relevant to no one, and whatever the viewer was sent of it ends
			flags = bit32.band(flags, bit32.bnot(RELEVANT + NEAR + CULLED))
			flags = settle(view, slot, flags, false, buffer.readu8(view.generations, slot))
			buffer.writeu16(view.flags, slot * 2, flags)
		end

		if not bit32.btest(flags, KEEP) then
			untrack(view, slot)
			continue
		end

		if bit32.btest(flags, HIDE) then
			hides += 1
			Hides[hides] = slot
		elseif not present then
			continue
		elseif bit32.btest(flags, REVEAL) then
			reveals += 1
			Reveals[reveals] = slot
		elseif bit32.btest(flags, LOOK + HELD) and bit32.btest(flags, SENT + OWN) then
			restyles += 1
			Restyles[restyles] = slot
		end

		if present and bit32.btest(flags, SENT) and not bit32.btest(flags, REVEAL + HIDE) then
			local state: State? = states[slot]
			if state then
				local listed: number = schedule(view, slot, flags, state.position - origin, facing)
				if listed == OWED then
					floors += 1
					Floors[floors] = slot
				elseif listed == QUEUED then
					fills += 1
					Fills[fills] = slot
				end
			end
		end
	end

	local used: number = Traffic(key)
	HardRoom = math.min(Hard / RelayRate, Hard - used)
	SoftRoom = math.min(Soft / RelayRate, Soft - used)
	Spent = 0

	for index: number = 1, hides do
		addHide(view, Hides[index])
	end

	for index: number = 1, reveals do
		addReveal(view, Reveals[index])
	end

	for index: number = 1, restyles do
		addLook(view, Restyles[index])
	end

	-- A culled enemy's steps go once, to each viewer it is culled from inside the step's range
	for index: number = 0, StepCount - 1 do
		local slot: number = buffer.readu16(StepSlots, index * 2)
		local flags: number = buffer.readu16(view.flags, slot * 2)

		if bit32.btest(flags, CULLED) and not bit32.btest(flags, SENT) then
			local offset: vector = StepPlaces[index + 1] - origin
			if vector.dot(offset, offset) <= Heard[buffer.readu8(StepKinds, index)] then
				addFootstep(view, index * FOOTSTEP_BYTES)
			end
		end
	end

	placeRecords(view, Floors, floors, HardRoom)
	placeRecords(view, Fills, fills, SoftRoom)
	flush()

	if view.watcherCount > 0 then
		withhold(view, states)
	end
end

--[[
    One relay tick: encodes each live body's record and footsteps once, a
    rider's in its platform's space where platforms holds that platform's
    place at the tick, then gives each viewer with no target its blocks,
    copied to the viewers watching it. states holds the server's live
    bodies by slot, and commands the command each last stepped, whose pitch
    and head offset its record carries. A target handed more watchers than
    it takes errors, naming it, once every viewer has had its turn
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
	end

	Run += 1
	TickWire = tick % WRAP
	StepCount = 0

	for slot: number, state: State in states do
		local generation: number, entry: Slots.Entry? = Slots.get(slot)
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
	end

	-- Every viewer's view, and which of them run their own this run
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

	local overfull: Key? = nil
	for _, viewer: Viewer in viewers do
		local target: Key? = viewer.target
		if target ~= nil and not watch(viewer, target) and overfull == nil then
			overfull = target
		end
	end

	for _, viewer: Viewer in viewers do
		if viewer.target == nil then
			turn(viewer, states)
		end
	end

	if overfull ~= nil then
		error(`{overfull.Name} has more than the {MAX_WATCHERS} watchers one target takes`, 2)
	end
end

-- Errors naming a value that is no slot, from the caller of the member named
local function checkSlot(slot: number, member: string)
	if not Slots.valid(slot) then
		error(`Relay.{member} takes one of the slot table's slots, not {slot}`, 3)
	end
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

	if on then
		local generation: number = Slots.get(slot)
		buffer.writeu8(Invisible, slot, generation + 1)
	else
		buffer.writeu8(Invisible, slot, 0)
	end
end

--[[
    A shooter's bullet passed near a viewer, so the shooter's record goes
    to it at no less than shotNear.rate for shotNear.seconds and weighs
    twice in its queue, while the viewer is sent the shooter
--]]

function Relay.shotNear(key: Key, slot: number)
	checkSlot(slot, "shotNear")

	local view: View? = Views[key]
	if view then
		buffer.writeu32(view.shotUntil, slot * 4, Run + ShotRuns)
	end
end

-- Whether a viewer's stretch of a slot belongs to the slot's current life and the viewer is sent it, which a
-- viewer watching a target, its own view set aside, never is
local function sentTo(view: View, slot: number, generation: number): boolean
	return view.watching == nil
		and bit32.btest(buffer.readu16(view.flags, slot * 2), SENT)
		and buffer.readu8(view.generations, slot) == generation
end

--[[
    Gives every viewer currently sent a slot a fresh pending reveal of it,
    with its record and its look in the same block, and no other viewer
    anything, as a sleeper's move needs
--]]

function Relay.reveal(slot: number)
	checkSlot(slot, "reveal")

	local generation: number = Slots.get(slot)
	for _, view: View in Views do
		if sentTo(view, slot, generation) then
			buffer.writeu16(view.flags, slot * 2, revealAgain(view, slot, buffer.readu16(view.flags, slot * 2)))
		end
	end
end

--[[
    Makes every character a viewer is currently sent a pending reveal again,
    with its look and held item in the same block, and its own character's
    look entry too, as a spectate's start and switch need of the target's
    view and its end of the moderator's own
--]]

function Relay.revealAll(key: Key)
	local view: View? = Views[key]
	if not view then
		return
	end

	for _, slot: number in view.tracked do
		local flags: number = buffer.readu16(view.flags, slot * 2)

		if bit32.btest(flags, SENT) then
			buffer.writeu16(view.flags, slot * 2, revealAgain(view, slot, flags))
		elseif bit32.btest(flags, OWN) then
			buffer.writeu16(view.flags, slot * 2, lookAgain(view, slot, flags))
		end
	end
end

--[[
    Whether a viewer is currently sent a slot's current life: from the tick
    its reveal was first carried until the tick its hide is
--]]

function Relay.isSent(key: Key, slot: number): boolean
	checkSlot(slot, "isSent")

	local view: View? = Views[key]
	if not view then
		return false
	end

	local generation: number = Slots.get(slot)

	return sentTo(view, slot, generation)
end

--[[
    The viewers currently sent a slot's current life, in a list of their
    own, for a cue the game sends only to the screens that show it
--]]

function Relay.viewersOf(slot: number): { Key }
	checkSlot(slot, "viewersOf")

	local generation: number = Slots.get(slot)
	local keys: { Key } = {}

	for key: Key, view: View in Views do
		if sentTo(view, slot, generation) then
			table.insert(keys, key)
		end
	end

	return keys
end

-- What a slot wears for a keyframe, each in a new buffer: its look when it is set for the life, and its held item
local function worn(slot: number, generation: number): (buffer, buffer)
	local look: buffer = buffer.create(0)
	if buffer.readu8(LookLives, slot) == generation + 1 then
		look = slice(Looks, slot * MAX_LOOK, buffer.readu8(LookLengths, slot))
	end

	return look, slice(Helds, slot * MAX_HELD, buffer.readu8(HeldLengths, slot))
end

-- A slot's character for a keyframe: its kind, newest record, look and held item
local function keyed(slot: number, kind: Block.Kind, withheld: boolean, generation: number): Keyframe.Character
	local look: buffer, held: buffer = worn(slot, generation)

	return {
		kind = kind,
		withheld = withheld,
		record = slice(Records, slot * RECORD_BYTES, RECORD_BYTES),
		look = look,
		held = held,
	}
end

-- A view's own character for a keyframe, as its last turn claimed it, or nil while it claimed none
local function ownOf(view: View): Keyframe.Own?
	local slot: number? = view.own
	if slot == nil or not bit32.btest(buffer.readu16(view.flags, slot * 2), OWN) then
		return nil
	end

	local generation: number = buffer.readu8(view.generations, slot)
	local look: buffer, held: buffer = worn(slot, generation)

	return { id = Record.id(slot, generation), look = look, held = held }
end

--[[
    A viewer's current view as one buffer a clip ring starts from: each
    character its client is sent with its kind, newest record, look and
    held item, the called platforms the server handle passes in, and its
    own character with its look and held item. A moderator watching a
    target is sent the target's view, so its keyframe holds the target's
    characters, its own character and, marked withheld, those withheld
    from the target, with their looks
--]]

function Relay.keyframe(key: Key, platforms: { Keyframe.Platform }?): buffer
	local characters: { Keyframe.Character } = {}
	local view: View? = Views[key]
	local sequence: number = 0
	local own: Keyframe.Own? = nil

	if view then
		sequence = view.heard

		local source: View = view
		local watching: Key? = view.watching
		if watching ~= nil then
			source = Views[watching] or view
		end

		own = ownOf(source)

		for _, slot: number in source.tracked do
			if bit32.btest(buffer.readu16(source.flags, slot * 2), SENT) then
				local kind: Block.Kind = Block.KINDS[buffer.readu8(source.kinds, slot) + 1]
				table.insert(characters, keyed(slot, kind, false, buffer.readu8(source.generations, slot)))
			end
		end

		-- The withheld set as the target's last turn left it, players alone
		local withheld: Withheld? = source.withheld
		if source ~= view and withheld then
			for _, slot: number in source.tracked do
				local life: number = buffer.readu8(withheld.lives, slot)
				if
					bit32.btest(buffer.readu8(withheld.flags, slot), WITHHELD)
					and life == buffer.readu8(Generations, slot)
				then
					table.insert(characters, keyed(slot, "Player", true, life))
				end
			end
		end
	end

	return Keyframe.write({
		hash = DeclarationsHash,
		tick = TickWire,
		sequence = sequence,
		characters = characters,
		platforms = platforms or {},
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

	viewOf(key).distance = math.min(distance, Radii.leave)
end

--[[
    Forgets a viewer that left, with everything pending for it
--]]

function Relay.remove(key: Key)
	Views[key] = nil
end

--[[
    The running totals since start of the records the tier ticks placed in
    a viewer's blocks, and of those the viewer's room left out
--]]

function Relay.counts(): (number, number)
	return RecordsSent, RecordsCut
end

return Relay
