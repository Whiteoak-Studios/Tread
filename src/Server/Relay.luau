--[[
    The relay: which characters each viewer is sent and how often inside its
    byte budget, and the blocks of their records, a culled enemy's
    footsteps, and the reveals, hides and looks that ride until acknowledged
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
local ENTRY_PARTS: number = 4
local VISIBILITY: number = 0 -- A reveal or a hide
local LOOK_PART: number = 1
local HELD_PART: number = 2

local STEP_START: number = 256 -- The steps one run holds before its buffers grow
local SILENT: number = -1 -- A squared range no step falls inside, for a kind the game gives no range

local UNSTARTED: string = "The relay sends nothing until Relay.start hands it its settings and its three functions"

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
}

-- What the relay keeps for one viewer: the slots it holds anything for, each field a buffer by slot, and the blocks
-- its acknowledgment can still name with the pending entries each carried
type View = {
	key: Key,
	sequence: number, -- The message sequence its next block takes
	newest: number, -- The sequence of the last block it was sent, 0 before the first
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
	log: buffer, -- u16 a pending entry
	logHead: number, -- The entries ever logged
}

-- What start hands in, each refusing until then
local Started: boolean = false

local Send: (key: Key, data: buffer) -> () = function (_: Key, _: buffer)
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

-- The game's settings as the relay reads them, each distance squared and each budget in bytes a second
local RelayRate: number = 0
local StillRuns: number = 0
local EnterSquared: number = 0
local LeaveSquared: number = 0
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
local SleeperSquared: number = 0
local NpcNearSquared: number = 0
local NpcRangeSquared: number = 0
local NpcFarRate: number = 0
local StrideWalk: number = 0
local StrideSprint: number = 0
local Heard: { number } = { SILENT, SILENT, SILENT, SILENT } -- Each footstep kind's squared range

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
    fires one block to a viewer, traffic is Volt's count of the bytes sent
    to it over the last second, and isHidden is anti-ESP's answer for a
    pair. It runs once
--]]

function Relay.start(
	settings: Settings,
	send: (key: Key, data: buffer) -> (),
	traffic: (key: Key) -> number,
	isHidden: (viewer: Viewer, slot: number) -> boolean
)
	if Started then
		error("Relay.start runs once, and it has already run", 2)
	elseif type(send) ~= "function" or type(traffic) ~= "function" or type(isHidden) ~= "function" then
		error("Relay.start takes send, traffic and isHidden as functions", 2)
	end

	local shared: Shared = settings.shared
	local server: ServerSettings = settings.server

	Started = true
	Send = send
	Traffic = traffic
	IsHidden = isHidden
	Layout = settings.layout
	DeclarationsHash = Fields.hash(settings.layout)
	Limits = { lean = shared.step.lean, headCone = shared.step.headCone }

	RelayRate = shared.rates.relay
	StillRuns = STILL_SECONDS * RelayRate
	EnterSquared = server.relevancy.enter ^ 2
	LeaveSquared = server.relevancy.leave ^ 2
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
	SleeperSquared = server.sleepers.radius ^ 2
	NpcNearSquared = server.npcs.near ^ 2
	NpcRangeSquared = server.npcs.range ^ 2
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
    the command it last stepped, which the step has already held to the cone
--]]

local function encode(slot: number, state: State, command: Command?, generation: number)
	local record: Record.Record = Scratch
	record.slot = slot
	record.generation = generation
	record.position = state.position
	record.yaw = state.facing
	record.word = StateWord.pack(state)
	record.lean = state.lean

	-- Whiteoak TODO: a rider's record carries its platform's id and its place in the platform's space once Platforms
	-- gives each platform's path at a tick; until then every record is in world coordinates
	record.platform = 0

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
	if length == buffer.readu8(HeldLengths, slot) and same(HeldScratch, Helds, at, length) then
		return
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

-- Whether a state stands in a gait that steps: on the ground, standing and walking, so a crouch, a crawl, a swim, a
-- climb, a mantle and the staff modes are silent
local function stepping(state: State): boolean
	return state.grounded and state.mode == "Ground" and state.posture == "Stand" and state.moveMode == "Walk"
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
			if state.sprint then
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

-- Each part of a slot's look pending again, its latest, when it changed since the viewer was last given it
local function restyle(view: View, slot: number, flags: number): number
	local look: number = buffer.readu16(LookVersions, slot * 2)
	if look ~= buffer.readu16(view.lookSent, slot * 2) then
		buffer.writeu16(view.lookSent, slot * 2, look)

		if dressed(slot) then
			flags = bit32.bor(bit32.band(flags, bit32.bnot(LOOK_CARRIED)), LOOK)
		end
	end

	local held: number = buffer.readu16(HeldVersions, slot * 2)
	if held ~= buffer.readu16(view.heldSent, slot * 2) then
		buffer.writeu16(view.heldSent, slot * 2, held)
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
end

--[[
    Clears one pending entry a block carried, once the viewer acknowledged
    it, unless the entry changed after that block, so a newer one waits
    for an acknowledgment of its own
--]]

local function clear(view: View, slot: number, part: number, sequence: number)
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

-- Clears what one block carried, once, when the block is still remembered and its entries still logged
local function receipt(view: View, sequence: number)
	local ring: number = sequence % RING
	if buffer.readu32(view.ringSequences, ring * 4) ~= sequence + 1 then
		return
	end

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

-- Takes in a viewer's acknowledgment: its newest sequence, 0 for none, and the mask of the 16 before it
local function acknowledge(view: View, newest: number, mask: number)
	if newest ~= 0 then
		receipt(view, newest)
	end

	for back: number = 1, MASK_BITS do
		if bit32.btest(mask, 2 ^ (back - 1)) then
			receipt(view, (newest - back) % WRAP)
		end
	end
end

-- Opens a viewer's next block of the tick, with the ring entry its acknowledgment will name
local function open(view: View)
	local sequence: number = view.sequence
	local ring: number = sequence % RING

	view.sequence = sequence % SEQUENCES + Constants.FIRST_SEQUENCE
	view.newest = sequence

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

-- Writes the open block into the buffer of its exact length and sends it
local function flush(view: View)
	if not Open then
		return
	end

	Open = false

	local data: buffer = exact(Filled)
	if Block.write(Out, data) ~= Filled then
		error("A relay block wrote other than the bytes the relay counted for it")
	end

	Send(view.key, data)
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
		flush(view)
		open(view)
	end

	Filled += bytes
	Spent += bytes

	return true
end

-- Logs a pending entry the open block carries, marking where it first rode since it last changed
local function carry(view: View, slot: number, part: number, flags: number, carried: number, from: buffer): number
	if not bit32.btest(flags, carried) then
		buffer.writeu16(from, slot * 2, Out.sequence)
		flags = bit32.bor(flags, carried)
	end

	local ring: number = (Out.sequence % RING) * 2
	buffer.writeu16(view.log, (view.logHead % LOG) * 2, slot * ENTRY_PARTS + part)
	buffer.writeu16(view.ringCounts, ring, buffer.readu16(view.ringCounts, ring) + 1)
	view.logHead += 1

	return flags
end

-- The bytes a look entry takes with the parts pending
local function lookBytes(slot: number, flags: number): number
	local bytes: number = LOOK_ENTRY_BYTES

	if bit32.btest(flags, LOOK) then
		bytes += PREFIX_BYTES + buffer.readu8(LookLengths, slot)
	end

	if bit32.btest(flags, HELD) then
		bytes += PREFIX_BYTES + buffer.readu8(HeldLengths, slot)
	end

	return bytes
end

-- The open block's look entry at count, its table made the first time a block holds that many, as are the others
local function lookEntry(count: number): Block.Look
	local kept: Block.Look? = Out.looks[count]
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
	Out.looks[count] = made

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

-- Puts a look entry with the parts pending into the open block, which has room for it
local function writeLook(view: View, slot: number, flags: number): number
	local count: number = Out.lookCount + 1
	local look: Block.Look = lookEntry(count)

	look.slot = slot
	look.generation = buffer.readu8(Generations, slot)
	look.look = bit32.btest(flags, LOOK)
	look.lookData = Looks
	look.lookAt = slot * MAX_LOOK
	look.lookLength = buffer.readu8(LookLengths, slot)
	look.held = bit32.btest(flags, HELD)
	look.heldData = Helds
	look.heldAt = slot * MAX_HELD
	look.heldLength = buffer.readu8(HeldLengths, slot)
	Out.lookCount = count

	if look.look then
		flags = carry(view, slot, LOOK_PART, flags, LOOK_CARRIED, view.lookFrom)
	end

	if look.held then
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

-- Takes the stale entries past count off the end of a list a turn refilled, so it sorts as exactly that long
local function trim(list: { number }, count: number)
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

--[[
    One viewer's turn: its acknowledgment, its own character, every body
    against it, then its blocks: pending hides, reveals and looks, the
    footsteps it can hear, the records it is owed inside the hard budget,
    and the rest inside the soft budget
--]]

-- What the relay keeps for a viewer, made on its first turn and kept until it is removed
local function viewOf(key: Key): View
	local kept: View? = Views[key]
	if kept then
		return kept
	end

	local made: View = {
		key = key,
		sequence = Constants.FIRST_SEQUENCE,
		newest = 0,
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
		log = buffer.create(LOG * 2),
		logHead = 0,
	}
	Views[key] = made

	return made
end

local function turn(viewer: Viewer, states: { [number]: State })
	local key: Key = viewer.key
	local view: View = viewOf(key)

	acknowledge(view, viewer.acknowledged, viewer.received)

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
	flush(view)
end

--[[
    One relay tick: encodes each live body's record and footsteps once,
    then gives each viewer its blocks. states holds the server's live
    bodies by slot, and commands the command each last stepped, whose pitch
    and head offset its record carries
--]]

function Relay.run(tick: number, viewers: { Viewer }, states: { [number]: State }, commands: { [number]: Command })
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

		encode(slot, state, commands[slot], generation)
		hold(slot, state.held)

		if kind == PLAYER or kind == NPC then
			walk(slot, state, generation)
		end
	end

	for _, viewer: Viewer in viewers do
		turn(viewer, states)
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

-- Whether a viewer's stretch of a slot belongs to the slot's current life and the viewer is sent it
local function sentTo(view: View, slot: number, generation: number): boolean
	return bit32.btest(buffer.readu16(view.flags, slot * 2), SENT)
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

-- A copy of length bytes of source from at, in a buffer of its own
local function slice(source: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, source, at, length)

	return part
end

--[[
    A viewer's current view as one buffer a clip ring starts from: each
    character it is sent with its kind, newest record, look and held item,
    and the called platforms the server handle passes in
--]]

function Relay.keyframe(key: Key, platforms: { Keyframe.Platform }?): buffer
	local characters: { Keyframe.Character } = {}
	local view: View? = Views[key]
	local sequence: number = 0

	if view then
		sequence = view.newest

		for _, slot: number in view.tracked do
			if not bit32.btest(buffer.readu16(view.flags, slot * 2), SENT) then
				continue
			end

			local look: buffer = buffer.create(0)
			if buffer.readu8(LookLives, slot) == buffer.readu8(view.generations, slot) + 1 then
				look = slice(Looks, slot * MAX_LOOK, buffer.readu8(LookLengths, slot))
			end

			table.insert(characters, {
				kind = Block.KINDS[buffer.readu8(view.kinds, slot) + 1],
				withheld = false,
				record = slice(Records, slot * RECORD_BYTES, RECORD_BYTES),
				look = look,
				held = slice(Helds, slot * MAX_HELD, buffer.readu8(HeldLengths, slot)),
			})
		end
	end

	return Keyframe.write({
		hash = DeclarationsHash,
		tick = TickWire,
		sequence = sequence,
		characters = characters,
		platforms = platforms or {},
	})
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
