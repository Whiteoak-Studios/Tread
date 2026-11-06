--[[
    Remote characters drawn at one render time behind the relay: each slot's
    8-record ring, the adaptive delay and time scale, the reveals, hides and
    looks held against the slot table, and a culled enemy's footstep entries
--]]

--!strict
--!native
local Block = require(script.Parent.Parent.Codec.Block)
local Command = require(script.Parent.Parent.Codec.Command)
local Constants = require(script.Parent.Parent.Constants)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Math = require(script.Parent.Parent.Step.Math)
local Record = require(script.Parent.Parent.Codec.Record)
local Reliable = require(script.Parent.Parent.Codec.Reliable)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.Parent.Codec.StateWord)

local SLOTS: number = Constants.SLOTS
local RECORD_BYTES: number = Constants.RECORD_BYTES
local RING: number = 8 -- The records each remote slot's ring keeps, the newest overwriting the oldest
local TICK_BYTES: number = 8 -- Each ring sample's relay tick, an f64 since it is unwrapped past the u16
local WIRE: number = 2 ^ 16 -- The values a u16 wire tick holds
local MASK: number = 2 ^ Constants.ACK_MASK_BITS - 1 -- The acknowledgment mask's bits
local GENERATIONS: number = 2 ^ Constants.GENERATION_BITS -- A generation wraps inside the record's bits beside the slot
local HALF_GENERATIONS: number = GENERATIONS / 2
local YAW_STEPS: number = Constants.ANGLE_STEPS / (2 * math.pi) -- Steps a radian of yaw, the units Sequence wraps
local REACH: number = 2 -- The last two samples' fraction one interval past the newer, where extrapolation stops

-- A slot's look entry parts, the look then the held item, each at most its declarations' bound
local LOOK_REGION: number = 0
local HELD_REGION: number = Constants.MAX_LOOK
local PART_BYTES: number = Constants.MAX_LOOK + Constants.MAX_HELD

type Footstep = Block.Footstep
type Hide = Block.Hide
type Kind = Block.Kind
type Look = Block.Look
type Entry = Reliable.Entry
type Layout = Fields.Layout
type Limits = Command.Limits
type Record = Record.Record
type State = State.State
type Values = State.Values
type Word = StateWord.Word

-- What an entry naming a slot and generation meets in the slot table: it applies, it waits for the table's entry,
-- or its life is over
type Verdict = "Apply" | "Hold" | "Ignore"

-- The client settings' interpolation block, in seconds and shares of real time
export type Settings = {
	delay: number, -- The render delay's floor, where it starts
	delayMax: number, -- Its ceiling, past which the render time snaps
	scaleMin: number, -- The time scale's range
	scaleMax: number,
}

-- The shared table's rates, in Hz
export type Rates = {
	simulation: number,
	relay: number,
}

export type RevealCallback = (slot: number, kind: Kind, player: Instance?, outfit: Values, held: Values?) -> ()
export type HideCallback = (slot: number) -> ()
export type DressCallback = (slot: number, outfit: Values) -> ()
export type HoldCallback = (slot: number, held: Values?) -> ()
export type FootstepCallback = (step: Footstep) -> ()

-- What start was given
local DelayBase: number = 0
local DelayMax: number = 0
local ScaleMin: number = 0
local ScaleMax: number = 0
local Rate: number = 0 -- Relay ticks a second
local LookLimits: Limits = { lean = 0, headCone = 0 } -- The lean and head cone a record's last byte steps to
local Declared: Layout? = nil -- The game's compiled declarations, which a look entry's parts unpack against
local Started: boolean = false

-- The render clock: the render time and the newest tick both count relay ticks, unwrapped from the first block's
local Clock: number = 0 -- Seconds the frames have advanced
local Receiving: boolean = false -- Whether a block has arrived
local Newest: number = 0 -- The newest block's relay tick
local NewestAt: number = 0 -- The clock when it arrived
local Delay: number = 0 -- Seconds the render time aims to run behind the newest tick
local RenderTime: number = 0
local Rendering: boolean = false -- Whether a frame has set the render time

-- What each Move acknowledges
local Acknowledged: number = 0 -- The newest relay sequence received
local Mask: number = 0 -- The 16 sequences before it, bit 0 for the one just before

-- The slot table, as its entries announce each slot
local Generations: { [number]: number } = {}
local Taken: { [number]: boolean } = {} -- False for a freed slot or a life a death ended
local Players: { [number]: Instance } = {} -- A live player's slot's Player

-- Each slot's stretch of being sent to this viewer, and its life's newest reveal or hide
local Kinds: { [number]: Kind } = {} -- An open stretch's kind
local Changed: { [number]: number } = {} -- The tick of the newest reveal or hide this life applied
local Hides: { [number]: number } = {} -- A hide's tick, which closes the stretch once the render time passes it
local Hiding: { number } = {} -- The slots that may have a hide waiting

-- Each slot's ring, by slot in buffers: the samples' ticks and records, the newest's place and how many it holds
local RingTicks: buffer = buffer.create(0)
local RingRecords: buffer = buffer.create(0)
local RingHeads: buffer = buffer.create(0)
local RingCounts: buffer = buffer.create(0)

-- Each slot's look entry parts as last applied: their bytes in Parts, lengths, blocks' ticks and values
local Parts: buffer = buffer.create(0)
local LookLengths: { [number]: number } = {}
local HeldLengths: { [number]: number } = {} -- 0 while the slot holds nothing
local LookTicks: { [number]: number } = {}
local HeldTicks: { [number]: number } = {}
local Outfits: { [number]: Values } = {}
local Helds: { [number]: Values } = {}

-- What waits for the slot table to announce its generation, the newest of each by slot
local HoldGenerations: { [number]: number } = {}
local HoldKinds: { [number]: Kind } = {} -- A reveal
local HoldRevealTicks: { [number]: number } = {}
local HoldRecordTicks: { [number]: number } = {} -- A record, its bytes in HoldRecords
local HoldLookTicks: { [number]: number } = {} -- Look entry parts, their bytes in HoldParts
local HoldLookLengths: { [number]: number } = {}
local HoldHeldLengths: { [number]: number } = {}
local HoldRecords: buffer = buffer.create(0)
local HoldParts: buffer = buffer.create(0)

-- What the reads reuse, so a block and a pose make no table
local Read: Block.Block = Block.new()
local Older: Record = Record.new()
local Newer: Record = Record.new()
local Earlier: Record = Record.new()
local Step: Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
local Other: Word = {
	mode = "Ground",
	posture = "Stand",
	sprint = false,
	aim = false,
	waterLevel = "Dry",
	jumps = 0,
	lands = 0,
	heavy = false,
	epoch = 0,
}

-- The callbacks of each signal, by the token their disconnect closure clears
local RevealListeners: { [{ nil }]: RevealCallback } = {}
local HideListeners: { [{ nil }]: HideCallback } = {}
local DressListeners: { [{ nil }]: DressCallback } = {}
local HoldListeners: { [{ nil }]: HoldCallback } = {}
local FootstepListeners: { [{ nil }]: FootstepCallback } = {}

local Interpolate = {}

--[[
    Starts the render clock from the client settings' interpolation block
    and the shared table's rates, with the lean and head cone a record's
    last byte steps to and the compiled declarations a look entry's parts
    unpack against. It runs once
--]]

function Interpolate.start(settings: Settings, rates: Rates, limits: Limits, layout: Layout)
	if Started then
		error("Interpolate.start runs once, and it has already run", 2)
	end

	DelayBase = settings.delay
	DelayMax = settings.delayMax
	ScaleMin = settings.scaleMin
	ScaleMax = settings.scaleMax
	Rate = rates.relay
	LookLimits = limits
	Declared = layout
	Delay = settings.delay

	RingTicks = buffer.create(SLOTS * RING * TICK_BYTES)
	RingRecords = buffer.create(SLOTS * RING * RECORD_BYTES)
	RingHeads = buffer.create(SLOTS)
	RingCounts = buffer.create(SLOTS)
	Parts = buffer.create(SLOTS * PART_BYTES)
	HoldRecords = buffer.create(SLOTS * RECORD_BYTES)
	HoldParts = buffer.create(SLOTS * PART_BYTES)

	Started = true
end

local function begun(member: string)
	if not Started then
		error(`Interpolate.{member} ran before Interpolate.start`, 3)
	end
end

-- Moves the acknowledgment to a block's sequence, newer ones shifting the mask and older ones setting their bit
local function acknowledge(sequence: number)
	if not Receiving then
		Acknowledged = sequence
		Mask = 0

		return
	end

	local ahead: number = Sequence.difference(sequence, Acknowledged)

	if ahead > 0 then
		if ahead > Constants.ACK_MASK_BITS then
			Mask = 0
		else
			-- The old newest lands on the highest bit the shift leaves clear
			Mask = bit32.band(bit32.bor(bit32.lshift(Mask, ahead), bit32.lshift(1, ahead - 1)), MASK)
		end

		Acknowledged = sequence
	elseif ahead < 0 and -ahead <= Constants.ACK_MASK_BITS then
		Mask = bit32.bor(Mask, bit32.lshift(1, -ahead - 1))
	end
end

--[[
    Unwraps a block's u16 tick against the newest, and for a newer one
    moves the newest and grows the delay by how much later than the clock
    expected it the block came, up to the ceiling
--]]

local function arrive(wire: number): number
	if not Receiving then
		Receiving = true
		Newest = wire
		NewestAt = Clock

		return wire
	end

	local tick: number = Newest + Sequence.difference(wire, Newest % WIRE)

	if tick > Newest then
		local late: number = (Newest + (Clock - NewestAt) * Rate - tick) / Rate

		Delay = math.min(math.max(Delay, DelayBase + late), DelayMax)
		Newest = tick
		NewestAt = Clock
	end

	return tick
end

-- The signed difference a - b of two generations, the shorter way round their wrap
local function generationsAhead(a: number, b: number): number
	return (a - b + HALF_GENERATIONS) % GENERATIONS - HALF_GENERATIONS
end

--[[
    What the slot table makes of an entry naming a slot and generation: an
    unannounced slot's or a newer generation's waits, an older generation's
    is ignored, as is the announced one's once the slot is freed or its
    life has died
--]]

local function judge(slot: number, generation: number): Verdict
	local announced: number? = Generations[slot]
	if announced == nil then
		return "Hold"
	end

	local ahead: number = generationsAhead(generation, announced)

	if ahead > 0 then
		return "Hold"
	elseif ahead < 0 or not Taken[slot] then
		return "Ignore"
	end

	return "Apply"
end

local function clearHold(slot: number)
	HoldGenerations[slot] = nil
	HoldKinds[slot] = nil
	HoldRevealTicks[slot] = nil
	HoldRecordTicks[slot] = nil
	HoldLookTicks[slot] = nil
	HoldLookLengths[slot] = nil
	HoldHeldLengths[slot] = nil
end

-- Whether a slot's hold keeps entries of a generation, emptied first for one newer than it holds
local function hold(slot: number, generation: number): boolean
	local held: number? = HoldGenerations[slot]

	if held ~= nil then
		local ahead: number = generationsAhead(generation, held)

		if ahead < 0 then
			return false
		elseif ahead == 0 then
			return true
		end
	end

	clearHold(slot)
	HoldGenerations[slot] = generation

	return true
end

-- A hide for a held generation drops the held reveal it comes after, and the record that came with it
local function unhold(slot: number, generation: number, tick: number)
	local revealTick: number? = HoldRevealTicks[slot]

	if HoldGenerations[slot] == generation and revealTick ~= nil and tick > revealTick then
		HoldKinds[slot] = nil
		HoldRevealTicks[slot] = nil
		HoldRecordTicks[slot] = nil
	end
end

local function holdReveal(slot: number, kind: Kind, tick: number)
	local held: number? = HoldRevealTicks[slot]

	if held == nil or tick > held then
		HoldKinds[slot] = kind
		HoldRevealTicks[slot] = tick
	end
end

local function holdRecord(slot: number, tick: number, data: buffer, offset: number)
	local held: number? = HoldRecordTicks[slot]

	if held == nil or tick > held then
		buffer.copy(HoldRecords, slot * RECORD_BYTES, data, offset, RECORD_BYTES)
		HoldRecordTicks[slot] = tick
	end
end

local function holdLook(slot: number, tick: number, look: Look)
	local offset: number = slot * PART_BYTES

	if look.look then
		buffer.copy(HoldParts, offset + LOOK_REGION, look.lookData, look.lookAt, look.lookLength)
		HoldLookLengths[slot] = look.lookLength
	end

	if look.held then
		buffer.copy(HoldParts, offset + HELD_REGION, look.heldData, look.heldAt, look.heldLength)
		HoldHeldLengths[slot] = look.heldLength
	end

	HoldLookTicks[slot] = tick
end

local function outfitOf(slot: number): Values
	local outfit: Values? = Outfits[slot]

	if outfit == nil then
		outfit = {}
		Outfits[slot] = outfit
	end

	return outfit :: Values
end

local function heldOf(slot: number): Values
	local held: Values? = Helds[slot]

	if held == nil then
		held = {}
		Helds[slot] = held
	end

	return held :: Values
end

-- What a slot holds now, nil for nothing
local function holding(slot: number): Values?
	local length: number? = HeldLengths[slot]

	if length == nil or length == 0 then
		return nil
	end

	return heldOf(slot)
end

-- Whether packed bytes differ from those a slot's part last applied at offset of Parts
local function differs(previous: number?, offset: number, data: buffer, at: number, length: number): boolean
	if previous ~= length then
		return true
	end

	for index: number = 0, length - 1 do
		if buffer.readu8(Parts, offset + index) ~= buffer.readu8(data, at + index) then
			return true
		end
	end

	return false
end

--[[
    Keeps a look entry's part as a slot's in Parts and says whether it
    changed. A block older than the one the part last came in, or the same
    bytes again, as each pending entry repeats until acknowledged, changes
    nothing
--]]

local function keep(
	slot: number,
	region: number,
	tick: number,
	data: buffer,
	at: number,
	length: number,
	lengths: { [number]: number },
	ticks: { [number]: number }
): boolean
	local last: number? = ticks[slot]
	if last ~= nil and tick < last then
		return false
	end

	ticks[slot] = tick

	local offset: number = slot * PART_BYTES + region
	if not differs(lengths[slot], offset, data, at, length) then
		return false
	end

	buffer.copy(Parts, offset, data, at, length)
	lengths[slot] = length

	return true
end

local function unpackPart(list: Fields.List, offset: number, length: number, into: Values)
	local failed: number? = Fields.read(list, Parts, offset, length, into)
	if failed then
		error(`A look entry's {list.name} part fails its declarations at field {failed}`)
	end
end

local function declared(): Layout
	local layout: Layout? = Declared
	if not layout then
		error("Interpolate unpacked a look before Interpolate.start")
	end

	return layout
end

-- Applies a look part, its new values told to every dress callback
local function dressLook(slot: number, tick: number, data: buffer, at: number, length: number)
	if not keep(slot, LOOK_REGION, tick, data, at, length, LookLengths, LookTicks) then
		return
	end

	local outfit: Values = outfitOf(slot)
	unpackPart(declared().slot, slot * PART_BYTES + LOOK_REGION, length, outfit)

	for _, callback: DressCallback in DressListeners do
		callback(slot, outfit)
	end
end

-- Applies a held part, one of length 0 holding nothing, told to every hold callback
local function dressHeld(slot: number, tick: number, data: buffer, at: number, length: number)
	if not keep(slot, HELD_REGION, tick, data, at, length, HeldLengths, HeldTicks) then
		return
	end

	if length > 0 then
		unpackPart(declared().held, slot * PART_BYTES + HELD_REGION, length, heldOf(slot))
	end

	local held: Values? = holding(slot)
	for _, callback: HoldCallback in HoldListeners do
		callback(slot, held)
	end
end

local function dress(slot: number, tick: number, look: Look)
	if look.look then
		dressLook(slot, tick, look.lookData, look.lookAt, look.lookLength)
	end

	if look.held then
		dressHeld(slot, tick, look.heldData, look.heldAt, look.heldLength)
	end
end

--[[
    Applies a reveal: a newer one than the life's last reveal or hide opens
    a stretch with an empty ring, marks a change of kind or takes back a
    hide still waiting, and an older one is a repeat from before it
--]]

local function reveal(slot: number, kind: Kind, tick: number)
	local last: number? = Changed[slot]
	if last ~= nil and tick <= last then
		return
	end

	Changed[slot] = tick
	Hides[slot] = nil

	local open: Kind? = Kinds[slot]
	if open == kind then
		return
	elseif open == nil then
		buffer.writeu8(RingCounts, slot, 0)
	end

	Kinds[slot] = kind

	local player: Instance? = Players[slot]
	local outfit: Values = outfitOf(slot)
	local held: Values? = holding(slot)

	for _, callback: RevealCallback in RevealListeners do
		callback(slot, kind, player, outfit, held)
	end
end

-- A hide newer than the life's last reveal or hide waits for the render time to pass its tick
local function hideAt(slot: number, tick: number)
	local last: number? = Changed[slot]
	if last ~= nil and tick <= last then
		return
	end

	Changed[slot] = tick

	if Kinds[slot] == nil or Hides[slot] ~= nil then
		return
	end

	Hides[slot] = tick

	if not table.find(Hiding, slot) then
		table.insert(Hiding, slot)
	end
end

-- Ends a slot's stretch and empties its ring
local function close(slot: number)
	Kinds[slot] = nil
	Hides[slot] = nil
	buffer.writeu8(RingCounts, slot, 0)
end

local function publishHide(slot: number)
	for _, callback: HideCallback in HideListeners do
		callback(slot)
	end
end

--[[
    Adds a record to an open stretch's ring as its newest sample. One no
    newer than the ring's newest, or past a hide still waiting, is dropped
--]]

local function push(slot: number, tick: number, data: buffer, offset: number)
	if Kinds[slot] == nil then
		return
	end

	local hide: number? = Hides[slot]
	if hide ~= nil and tick > hide then
		return
	end

	local base: number = slot * RING
	local count: number = buffer.readu8(RingCounts, slot)
	local head: number = buffer.readu8(RingHeads, slot)

	if count > 0 then
		if tick <= buffer.readf64(RingTicks, (base + head) * TICK_BYTES) then
			return
		end

		head = (head + 1) % RING
	else
		head = 0
	end

	buffer.writef64(RingTicks, (base + head) * TICK_BYTES, tick)
	buffer.copy(RingRecords, (base + head) * RECORD_BYTES, data, offset, RECORD_BYTES)
	buffer.writeu8(RingHeads, slot, head)
	buffer.writeu8(RingCounts, slot, math.min(count + 1, RING))
end

--[[
    Reads one relay block: acknowledges its sequence, moves the newest tick
    and the delay, then applies its hides, looks, reveals, records and
    footstep entries in that order, so a reveal carries the look its block
    brought. An entry for a generation the slot table hasn't announced
    waits for it, and one for an older generation is dropped. It errors on
    a block that isn't one
--]]

function Interpolate.receive(data: buffer)
	begun("receive")
	Block.read(data, Read)
	acknowledge(Read.sequence)

	local tick: number = arrive(Read.tick)

	for index: number = 1, Read.hideCount do
		local hide: Hide = Read.hides[index]
		local verdict: Verdict = judge(hide.slot, hide.generation)

		if verdict == "Apply" then
			hideAt(hide.slot, tick)
		elseif verdict == "Hold" then
			unhold(hide.slot, hide.generation, tick)
		end
	end

	for index: number = 1, Read.lookCount do
		local look: Look = Read.looks[index]
		local verdict: Verdict = judge(look.slot, look.generation)

		if verdict == "Apply" then
			dress(look.slot, tick, look)
		elseif verdict == "Hold" and hold(look.slot, look.generation) then
			holdLook(look.slot, tick, look)
		end
	end

	for index: number = 1, Read.revealCount do
		local entry: Block.Reveal = Read.reveals[index]
		local verdict: Verdict = judge(entry.slot, entry.generation)

		if verdict == "Apply" then
			reveal(entry.slot, entry.kind, tick)
		elseif verdict == "Hold" and hold(entry.slot, entry.generation) then
			holdReveal(entry.slot, entry.kind, tick)
		end
	end

	local records: buffer = Read.recordData
	for index: number = 1, Read.recordCount do
		local offset: number = Read.records[index]
		local slot: number, generation: number = Record.split(buffer.readu16(records, offset))
		local verdict: Verdict = judge(slot, generation)

		if verdict == "Apply" then
			push(slot, tick, records, offset)
		elseif verdict == "Hold" and hold(slot, generation) then
			holdRecord(slot, tick, records, offset)
		end
	end

	-- A footstep entry names no player, so every one goes on as it comes
	for index: number = 1, Read.footstepCount do
		Block.readFootstep(Read.footstepData, Read.footsteps[index], Step)

		for _, callback: FootstepCallback in FootstepListeners do
			callback(Step)
		end
	end
end

--[[
    The newest relay sequence received and the mask of the 16 before it,
    bit 0 for the one just before, which each Move sends back; 0 and 0
    before any block
--]]

function Interpolate.received(): (number, number)
	return Acknowledged, Mask
end

--[[
    Advances the render time by a frame toward the delay behind the newest
    tick the clock estimates, at the time scale that closes its drift in
    seconds within the scale's range. The delay eases back toward its
    floor, and each hide the render time passes closes its stretch

    @ dt | the frame's seconds, 0 or more
--]]

function Interpolate.frame(dt: number)
	begun("frame")
	if not (dt >= 0 and dt < math.huge) then
		error(`Interpolate.frame takes the frame's seconds, 0 or more, not {dt}`, 2)
	end

	-- The delay comes back down no faster than the time scale lets the render time catch up
	Clock += dt
	Delay = math.max(DelayBase, Delay - (ScaleMax - 1) * dt)

	if not Receiving then
		return
	end

	local newest: number = Newest + (Clock - NewestAt) * Rate
	local target: number = newest - Delay * Rate

	if Rendering then
		-- The seconds it would still be off its aim after running at real time this frame
		local drift: number = (target - RenderTime) / Rate - dt
		local scale: number = math.clamp(1 + drift, ScaleMin, ScaleMax)

		RenderTime += dt * Rate * scale
	end

	-- Snaps to its aim on the first frame, and once it falls more than delayMax behind the newest tick or passes it
	local behind: number = (newest - RenderTime) / Rate
	if not Rendering or behind > DelayMax or behind < 0 then
		RenderTime = target
		Rendering = true
	end

	-- Backward, so a hide taken out swaps in one already passed
	for index: number = #Hiding, 1, -1 do
		local slot: number = Hiding[index]
		local hide: number? = Hides[slot]

		if hide == nil or hide <= RenderTime then
			Hiding[index] = Hiding[#Hiding]
			table.remove(Hiding)

			if hide ~= nil then
				close(slot)
				publishHide(slot)
			end
		end
	end
end

--[[
    The render time remote characters are drawn at, in relay ticks with
    their fraction, unwrapped from the first block's tick so its whole
    ticks' low 16 bits are the wire's
--]]

function Interpolate.renderTime(): number
	return RenderTime
end

--[[
    The delay the render time aims to run behind the newest tick, in
    seconds, which each Move reports
--]]

function Interpolate.delay(): number
	return Delay
end

local function tickOf(base: number, head: number, back: number): number
	return buffer.readf64(RingTicks, (base + (head - back) % RING) * TICK_BYTES)
end

local function recordOf(base: number, head: number, back: number): number
	return (base + (head - back) % RING) * RECORD_BYTES
end

--[[
    Fills into with a remote slot's drawn state at the render time and
    gives whether it has one, with the aim pitch in radians, which a state
    holds none of. Every value goes through the one lerp, yaw on the
    shortest arc, and velocity comes from the two samples drawn between.
    The state word, its epoch the 2-bit parity, the platform and grounded
    come from the sample at or before the render time; nothing else changes
--]]

function Interpolate.pose(slot: number, into: State): (boolean, number)
	begun("pose")
	if not (slot >= 0 and slot < SLOTS and slot % 1 == 0) then
		error(`Interpolate.pose takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	end

	local count: number = buffer.readu8(RingCounts, slot)
	if count == 0 then
		return false, 0
	end

	local base: number = slot * RING
	local head: number = buffer.readu8(RingHeads, slot)

	-- How far back from the newest the last sample at or before the render time sits
	local back: number = 0
	while back < count and tickOf(base, head, back) > RenderTime do
		back += 1
	end

	if back == count then
		return false, 0
	end

	-- Between it and the next newer sample, or past the newest along the last two, or one sample alone
	local older: number = back
	local newer: number = back - 1
	if back == 0 then
		older = math.min(1, count - 1)
		newer = 0
	end

	local olderTick: number = tickOf(base, head, older)
	local newerTick: number = tickOf(base, head, newer)
	Record.read(RingRecords, recordOf(base, head, older), Older, LookLimits)
	Record.read(RingRecords, recordOf(base, head, newer), Newer, LookLimits)

	local from: Record = back == 0 and Newer or Older
	local other: Record = back == 0 and Older or Newer
	StateWord.unpack(from.word, into)
	StateWord.unpack(other.word, Other)

	-- The sample at or before the render time is drawn as it is, and never toward one on another platform or epoch
	local span: number = newerTick - olderTick
	local t: number = back == 0 and 1 or 0
	local still: boolean = span <= 0 or Older.platform ~= Newer.platform or into.epoch ~= Other.epoch

	if not still and back == 0 then
		-- Past the newest, along the last two for one interval more, where it holds
		t = math.min((RenderTime - olderTick) / span, REACH)
	elseif not still then
		-- A move from rest began inside the interval the samples after it keep, not across the gap from rest
		if older + 1 < count and newer > 0 then
			Record.read(RingRecords, recordOf(base, head, older + 1), Earlier, LookLimits)

			if Earlier.position == Older.position then
				span = math.min(span, tickOf(base, head, newer - 1) - newerTick)
			end
		end

		t = (RenderTime - (newerTick - span)) / span

		if t < 0 then
			t = 0
			still = true
		end
	end

	local olderAt: vector = Older.position
	local newerAt: vector = Newer.position
	local olderYaw: number = Older.yaw * YAW_STEPS
	local newerYaw: number = olderYaw + Sequence.difference(Newer.yaw * YAW_STEPS, olderYaw)
	local yaw: number = Math.lerp(olderYaw, newerYaw, t)

	into.position = vector.create(
		Math.lerp(olderAt.x, newerAt.x, t),
		Math.lerp(olderAt.y, newerAt.y, t),
		Math.lerp(olderAt.z, newerAt.z, t)
	)
	into.facing = (yaw % Constants.ANGLE_STEPS) / YAW_STEPS
	into.lean = Math.lerp(Older.lean, Newer.lean, t)
	into.platform = from.platform
	into.grounded = into.mode == "Ground"

	if still then
		into.velocity = vector.zero
	else
		into.velocity = (newerAt - olderAt) * (Rate / span)
	end

	return true, Math.lerp(Older.pitch, Newer.pitch, t)
end

--[[
    Announces a slot's life: a freed slot or a new generation ends the
    life drawn now, told to every hide callback, and a new generation
    starts with no reveal, hide or look of its own
--]]

local function announce(slot: number, generation: number, taken: boolean, player: Instance?)
	local renewed: boolean = Generations[slot] ~= generation

	if Kinds[slot] ~= nil and (renewed or not taken) then
		close(slot)
		publishHide(slot)
	end

	if renewed then
		Changed[slot] = nil
		LookLengths[slot] = nil
		HeldLengths[slot] = nil
		LookTicks[slot] = nil
		HeldTicks[slot] = nil
	end

	Generations[slot] = generation
	Taken[slot] = taken
	Players[slot] = player
end

-- Applies what a slot's hold kept once the table announces its generation, or drops it for a life already over
local function release(slot: number)
	local generation: number? = HoldGenerations[slot]
	if generation == nil then
		return
	end

	local verdict: Verdict = judge(slot, generation)
	if verdict == "Hold" then
		return
	end

	if verdict == "Apply" then
		local offset: number = slot * PART_BYTES
		local lookTick: number? = HoldLookTicks[slot]
		local lookLength: number? = HoldLookLengths[slot]
		local heldLength: number? = HoldHeldLengths[slot]

		if lookTick ~= nil and lookLength ~= nil then
			dressLook(slot, lookTick, HoldParts, offset + LOOK_REGION, lookLength)
		end

		if lookTick ~= nil and heldLength ~= nil then
			dressHeld(slot, lookTick, HoldParts, offset + HELD_REGION, heldLength)
		end

		local kind: Kind? = HoldKinds[slot]
		local revealTick: number? = HoldRevealTicks[slot]
		if kind ~= nil and revealTick ~= nil then
			reveal(slot, kind, revealTick)
		end

		local recordTick: number? = HoldRecordTicks[slot]
		if recordTick ~= nil then
			push(slot, recordTick, HoldRecords, slot * RECORD_BYTES)
		end
	end

	clearHold(slot)
end

--[[
    Takes the slot table's entries as Volt's Slots sends them, in order:
    each announces its slot's generation, ends a life it replaces or frees,
    and lets go of the entries its slot held for that generation
--]]

function Interpolate.slots(entries: { Entry })
	begun("slots")

	for _, entry: Entry in entries do
		local slot: number, generation: number, rig: Reliable.Rig?, player: Instance? = Reliable.read(entry)

		announce(slot, generation, rig ~= nil, player)
		release(slot)
	end
end

--[[
    Takes a death message as Volt's Death sends it. The dying life's
    stretch ends with no hide, since the rig drawing it becomes the body's
    ragdoll, and later entries for that life are ignored. Gives the dying
    slot, the body's slot and the push for the ragdoll
--]]

function Interpolate.death(
	character: number,
	body: number,
	pushX: number,
	pushY: number,
	pushZ: number
): (number, number, vector)
	begun("death")

	local slot: number, generation: number, bodySlot: number, _: number, direction: vector =
		Reliable.readDeath(character, body, pushX, pushY, pushZ)

	if Generations[slot] == generation then
		Taken[slot] = false
		close(slot)
	end

	if HoldGenerations[slot] == generation then
		clearHold(slot)
	end

	return slot, bodySlot, direction
end

local function connect<T>(listeners: { [{ nil }]: T }, callback: T, member: string): () -> ()
	if type(callback) ~= "function" then
		error(`Interpolate.{member} takes a function, not a {typeof(callback)}`, 3)
	end

	local token: { nil } = {}
	listeners[token] = callback

	return function ()
		listeners[token] = nil
	end
end

--[[
    Calls back on each stretch a remote slot starts being sent, and on each
    change of its kind, with the slot table's player for a live player's,
    its look and its held item, nil for nothing. Returns the closure that
    disconnects the callback
--]]

function Interpolate.onReveal(callback: RevealCallback): () -> ()
	return connect(RevealListeners, callback, "onReveal")
end

--[[
    Calls back when a slot's stretch ends: once the render time passes its
    hide, or at once when the slot table frees the slot or gives it a new
    life. Returns the closure that disconnects the callback
--]]

function Interpolate.onHide(callback: HideCallback): () -> ()
	return connect(HideListeners, callback, "onHide")
end

--[[
    Calls back on each change of a slot's look, the viewer's own slot's
    included, with its values, a table each slot keeps and refills.
    Returns the closure that disconnects the callback
--]]

function Interpolate.onDress(callback: DressCallback): () -> ()
	return connect(DressListeners, callback, "onDress")
end

--[[
    Calls back on each change of a slot's held item, nil for nothing held,
    the viewer's own slot's included. Returns the closure that disconnects
    the callback
--]]

function Interpolate.onHold(callback: HoldCallback): () -> ()
	return connect(HoldListeners, callback, "onHold")
end

--[[
    Calls back on each footstep entry a block carries, a culled enemy's
    step, in one table each call refills, so a callback copies what it
    keeps. Returns the closure that disconnects the callback
--]]

function Interpolate.onFootstep(callback: FootstepCallback): () -> ()
	return connect(FootstepListeners, callback, "onFootstep")
end

return Interpolate
