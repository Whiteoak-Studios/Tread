--[[
    The server's hit history: a 24 B sample a body each relay tick, held for
    the history's length, the sample a hit test reads at a render time with
    its hit shapes placed, and the render time a shot rewinds to
--]]

--!strict
--!native
local Config = require(script.Parent.Parent.Config)
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Parent.Step.Engine)
local Math = require(script.Parent.Parent.Step.Math)
local Record = require(script.Parent.Parent.Codec.Record)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local Slots = require(script.Parent.Slots)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.Parent.Codec.StateWord)

local SLOTS: number = Constants.SLOTS
local ANGLE_STEPS: number = Constants.ANGLE_STEPS
local YAW_SCALE: number = ANGLE_STEPS / (2 * math.pi) -- Steps a radian of yaw
local PITCH_SCALE: number = Constants.PITCH_LIMIT / (math.pi / 2) -- Steps a radian of pitch, a quarter turn at 90°
local LEAN_STEPS: number = Constants.LEAN_STEPS
local DEGREES: number = math.pi / 180 -- Radians a degree of lean
local TICK_WRAP: number = 2 ^ 16 -- The ticks a sample's u16 tick holds
local EPOCH_BITS: number = 8 -- The full epoch's u8
local TIME_WRAP: number = 2 ^ 32 -- The milliseconds a sample's u32 server time holds
local MILLISECONDS: number = 1000 -- A second's

-- A platform id's low bits ride the top of the position's X and its high bits the top of its Z, as in a record
local PLATFORM_LOW: number = Constants.RECORD_TOP_BITS
local PLATFORM_HIGH: number = Constants.PLATFORM_BITS - Constants.RECORD_TOP_BITS

-- The 24 B sample: the relay tick, the server time, the position as a record holds it with the platform's id, yaw,
-- pitch, the state word, lean, the full epoch, the flags and a spare byte
local SAMPLE_BYTES: number = 24
local TICK_AT: number = 0
local TIME_AT: number = 2
local POSITION_AT: number = 6
local YAW_AT: number = 14
local PITCH_AT: number = 16
local WORD_AT: number = 18
local LEAN_AT: number = 20
local EPOCH_AT: number = 21
local FLAGS_AT: number = 22
local SPARE_AT: number = 23

-- The flags byte's bits
local LYING: number = 1 -- A sleeper's lying sample written at wake, hit through its Downed shapes
local ABSENT: number = 2 -- A tick the body spent in Noclip or Parked, which no hit test finds

type Posture = State.Posture
type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type State = State.State
type Word = StateWord.Word

-- One capsule of a hit shape, on the step's vector: in the character's own space, or placed in the world
export type Shape = {
	from: vector,
	to: vector,
	radius: number,
}

-- A body's state at a render time for a hit test. Each slot has one, rewritten by the next sampleAt for the slot
export type Sample = {
	epoch: number,
	position: vector, -- The feet, in world coordinates, or in its platform's frame while it rides one
	platform: number, -- The ridden platform's id, 0 for none
	yaw: number, -- Radians
	posture: Posture, -- The posture whose shapes are placed: Crouch for a swimmer and Downed for a lying sleeper
	body: Shape, -- The body capsule, placed in the frame its position is in
	zones: { [string]: Shape }, -- The zone capsules by name, placed the same way
}

-- What a woken sleeper's lying sample holds, which a sleeper's own Sample gives
export type Lying = {
	epoch: number,
	position: vector,
	platform: number,
	yaw: number,
}

-- One posture's hit shapes as the shared table's hitShapes give them
type GameShapes = {
	body: Config.Shape,
	zones: { [string]: Config.Shape },
	waist: number,
}

-- One posture's hit shapes crossed onto vector, and the height a lean tilts every point above about
type Shapes = {
	body: Shape,
	zones: { [string]: Shape },
	waist: number,
}

-- A slot's placed shapes for one posture, which its Sample points at
type Placed = {
	body: Shape,
	zones: { [string]: Shape },
}

local Buffers: { [number]: buffer } = {} -- Each slot's ring of samples, a tick at its tick's index, kept through its lives
local Newest: { [number]: number } = {} -- Each slot's newest tick written, nil while it holds no history
local Oldest: { [number]: number } = {} -- The tick its current history starts at
local Samples: { [number]: Sample } = {} -- Each slot's Sample, made on its first read
local PlacedShapes: { [number]: { [Posture]: Placed } } = {}
local Postures: { [Posture]: Shapes } = {} -- The shared table's hit shapes, crossed at start

-- The state word a sample holds, unpacked or packed in place
local Scratch: Word = {
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

local Present: number? = nil -- The newest relay tick any sample was written or seeded at
local Capacity: number = 0 -- Samples a slot's ring holds, the history's length in relay ticks and the tick at its end
local StartedAt: number = 0 -- The os.clock a sample's server time counts from
local Started: boolean = false

-- The settings start reads
local SimulationRate: number = 0 -- Hz
local RelayRate: number = 0
local QueueWait: number = 0 -- Simulation ticks a shot's queue wait counts at most
local LeanLimit: number = 0 -- Degrees
local Ceiling: number = 0 -- Seconds
local RttCap: number = 0
local DelayMin: number = 0
local DelayMax: number = 0
local Extra: number = 0 -- Relay ticks
local Band: number = 0
local BandSigmas: number = 0
local BandMax: number = 0

local History = {}

local function crossShape(shape: Config.Shape): Shape
	return { from = Engine.toVector(shape.from), to = Engine.toVector(shape.to), radius = shape.radius }
end

local function crossShapes(shapes: GameShapes): Shapes
	local zones: { [string]: Shape } = {}

	for name: string, shape: Config.Shape in shapes.zones do
		zones[name] = crossShape(shape)
	end

	return { body = crossShape(shapes.body), zones = zones, waist = shapes.waist }
end

--[[
    Takes the settings the history reads: the shared table's rates, its
    queue-wait cap, its lean limit and its hit shapes, and the server
    settings' history length and rewind terms. It runs once, before any
    other call, on tables Config.server has already checked
--]]

function History.start(shared: Shared, server: ServerSettings)
	if Started then
		error("History.start runs once, and it has already run", 2)
	end

	SimulationRate = shared.rates.simulation
	RelayRate = shared.rates.relay
	QueueWait = shared.ticks.queueWait
	LeanLimit = shared.step.lean
	Capacity = math.ceil(server.history.seconds * RelayRate) + 1

	Ceiling = server.rewind.ceiling
	RttCap = server.rewind.rttCap
	DelayMin = server.rewind.delayMin
	DelayMax = server.rewind.delayMax
	Extra = server.rewind.extra
	Band = server.rewind.band
	BandSigmas = server.rewind.bandSigmas
	BandMax = server.rewind.bandMax

	Postures.Stand = crossShapes(shared.hitShapes.Stand)
	Postures.Crouch = crossShapes(shared.hitShapes.Crouch)
	Postures.Downed = crossShapes(shared.hitShapes.Downed)

	StartedAt = os.clock()
	Started = true
end

local function isWhole(value: number): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function isFinite(value: number): boolean
	return type(value) == "number" and math.abs(value) < math.huge
end

-- A rewind's time or tick count, finite and not below 0
local function isTerm(value: number): boolean
	return isFinite(value) and value >= 0
end

local function offsetOf(tick: number): number
	return (tick % Capacity) * SAMPLE_BYTES
end

local function bufferFor(slot: number): buffer
	local data: buffer? = Buffers[slot]
	if data then
		return data
	end

	local made: buffer = buffer.create(Capacity * SAMPLE_BYTES)
	Buffers[slot] = made

	return made
end

-- Errors at the caller's caller on a platform or an epoch the sample's bits don't hold, before anything is written
local function checkWidths(platform: number, epoch: number)
	if bit32.extract(platform, 0, Constants.PLATFORM_BITS) ~= platform then
		error(`A sample's platform is 0 to {Constants.MAX_PLATFORMS}, not {platform}`, 3)
	elseif bit32.extract(epoch, 0, EPOCH_BITS) ~= epoch then
		error(`A sample's epoch is a u8 from 0 to {2 ^ EPOCH_BITS - 1}, not {epoch}`, 3)
	end
end

-- Moves the newest tick any sample names on to a tick past it
local function advance(tick: number)
	local present: number? = Present
	if present == nil or tick > present then
		Present = tick
	end
end

--[[
    Writes one sample at its tick's index, each value in the unit the step
    or the lying sample gives it, its platform and epoch already checked
--]]

local function encode(
	data: buffer,
	tick: number,
	position: vector,
	platform: number,
	yaw: number,
	pitch: number,
	word: number,
	lean: number,
	epoch: number,
	flags: number
)
	local offset: number = offsetOf(tick)
	local time: number = math.floor((os.clock() - StartedAt) * MILLISECONDS) % TIME_WRAP
	local xTop: number = bit32.extract(platform, 0, PLATFORM_LOW)
	local zTop: number = bit32.extract(platform, PLATFORM_LOW, PLATFORM_HIGH)

	buffer.writeu16(data, offset + TICK_AT, tick % TICK_WRAP)
	buffer.writeu32(data, offset + TIME_AT, time)
	Record.writePosition(position, xTop, zTop, data, offset + POSITION_AT)
	buffer.writeu16(data, offset + YAW_AT, math.round(yaw * YAW_SCALE) % ANGLE_STEPS)
	buffer.writei16(
		data,
		offset + PITCH_AT,
		math.clamp(math.round(pitch * PITCH_SCALE), -Constants.PITCH_LIMIT, Constants.PITCH_LIMIT)
	)
	buffer.writeu16(data, offset + WORD_AT, word)
	buffer.writei8(
		data,
		offset + LEAN_AT,
		math.clamp(math.round(lean / LeanLimit * LEAN_STEPS), -LEAN_STEPS, LEAN_STEPS)
	)
	buffer.writeu8(data, offset + EPOCH_AT, epoch)
	buffer.writeu8(data, offset + FLAGS_AT, flags)
	buffer.writeu8(data, offset + SPARE_AT, 0)
end

-- Copies the sample at one tick's index to another tick's, as that tick's
local function hold(data: buffer, from: number, tick: number)
	local offset: number = offsetOf(tick)

	buffer.copy(data, offset, data, offsetOf(from), SAMPLE_BYTES)
	buffer.writeu16(data, offset + TICK_AT, tick % TICK_WRAP)
end

--[[
    Writes a body's sample for a relay tick, from the state the tick's step
    left. A body in Noclip or Parked gets a tick no hit test finds. A tick
    past the slot's last sample holds that sample at every tick between,
    so an idle NPC's last sample answers for every time since it stopped

    @ tick | the relay tick as the server counts it, unwrapped, newer than the slot's last
    @ pitch | the pitch of the command it stepped, radians, since the state holds none
    @ platformAt | the ridden platform's position at the tick, which a rider's sample is held relative to
--]]

function History.write(slot: number, tick: number, state: State, pitch: number, platformAt: vector?)
	if not Started then
		error("History.write ran before History.start", 2)
	elseif not Slots.valid(slot) then
		error(`History.write takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	elseif not isWhole(tick) then
		error(`History.write takes the relay tick as a whole number of 0 or more, not {tick}`, 2)
	end

	local newest: number? = Newest[slot]
	if newest and tick <= newest then
		error(`History.write took tick {tick} for slot {slot}, which already holds tick {newest}`, 2)
	end

	checkWidths(state.platform, state.epoch)

	local position: vector = state.position
	if state.platform ~= 0 then
		if platformAt == nil then
			error(`Slot {slot} rides platform {state.platform}, so its sample needs the platform's position`, 2)
		end

		position -= platformAt
	end

	-- Every refusal comes before the ring changes, so a refused write leaves the slot as it was
	local word: number = StateWord.pack(state)
	local flags: number = state.moveMode == "Walk" and 0 or ABSENT
	local data: buffer = bufferFor(slot)

	-- Before the new sample, which may land on the last one's index
	if newest then
		for held: number = math.max(newest + 1, tick - Capacity + 1), tick - 1 do
			hold(data, newest, held)
		end
	else
		Oldest[slot] = tick
	end

	encode(data, tick, position, state.platform, state.facing, pitch, word, state.lean, state.epoch, flags)

	Newest[slot] = tick
	advance(tick)
end

--[[
    Writes a woken sleeper's lying sample, flagged lying, so it answers
    with the Downed shapes for every time the history holds up to the
    tick, and replaces whatever the slot held. The wake bumps the epoch,
    so no read crosses from it to the woken character's own samples

    @ tick | the relay tick of the wake, which the woken character's first write must pass
--]]

function History.seed(slot: number, tick: number, lying: Lying)
	if not Started then
		error("History.seed ran before History.start", 2)
	elseif not Slots.valid(slot) then
		error(`History.seed takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	elseif not isWhole(tick) then
		error(`History.seed takes the relay tick as a whole number of 0 or more, not {tick}`, 2)
	end

	checkWidths(lying.platform, lying.epoch)

	Scratch.mode = "Ground"
	Scratch.posture = "Downed"
	Scratch.sprint = false
	Scratch.aim = false
	Scratch.waterLevel = "Dry"
	Scratch.jumps = 0
	Scratch.lands = 0
	Scratch.heavy = false
	Scratch.epoch = lying.epoch

	local data: buffer = bufferFor(slot)
	local first: number = tick - Capacity + 1
	encode(data, first, lying.position, lying.platform, lying.yaw, 0, StateWord.pack(Scratch), 0, lying.epoch, LYING)

	for held: number = first + 1, tick do
		hold(data, first, held)
	end

	Oldest[slot] = first
	Newest[slot] = tick
	advance(tick)
end

--[[
    Drops a slot's history, for a death, a leave or a sleep, so it answers
    no read until its next life writes. The slot keeps its buffer
--]]

function History.clear(slot: number)
	if not Slots.valid(slot) then
		error(`History.clear takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	end

	Newest[slot] = nil
	Oldest[slot] = nil
end

-- The offset of a tick's sample, erroring if its index holds another tick's, which only a broken ring could leave
local function entry(data: buffer, tick: number): number
	local offset: number = offsetOf(tick)
	if buffer.readu16(data, offset + TICK_AT) ~= tick % TICK_WRAP then
		error(`The history's ring holds no sample for tick {tick} at its index`)
	end

	return offset
end

local function absent(data: buffer, offset: number): boolean
	return bit32.btest(buffer.readu8(data, offset + FLAGS_AT), ABSENT)
end

local function platformOf(xTop: number, zTop: number): number
	return xTop + zTop * 2 ^ PLATFORM_LOW
end

local function leanOf(data: buffer, offset: number): number
	return buffer.readi8(data, offset + LEAN_AT) * LeanLimit / LEAN_STEPS
end

-- A slot's Sample and its placed shapes for each posture, made on its first read and reused from then on
local function sampleFor(slot: number): Sample
	local sample: Sample? = Samples[slot]
	if sample then
		return sample
	end

	local placed: { [Posture]: Placed } = {}

	for posture: Posture, shapes: Shapes in Postures do
		local zones: { [string]: Shape } = {}

		for name: string, shape: Shape in shapes.zones do
			zones[name] = { from = shape.from, to = shape.to, radius = shape.radius }
		end

		placed[posture] =
			{ body = { from = shapes.body.from, to = shapes.body.to, radius = shapes.body.radius }, zones = zones }
	end

	local made: Sample = {
		epoch = 0,
		position = vector.zero,
		platform = 0,
		yaw = 0,
		posture = "Stand",
		body = placed.Stand.body,
		zones = placed.Stand.zones,
	}

	PlacedShapes[slot] = placed
	Samples[slot] = made

	return made
end

--[[
    A point of a shape in the character's own space, placed: tilted by the
    lean about the waist when it sits above it, a positive lean to the
    right, then turned by the yaw and moved to the feet. Own space has +X
    right and +Z back, as the step reads it
--]]

local function point(
	at: vector,
	feet: vector,
	sine: number,
	cosine: number,
	waist: number,
	leanSine: number,
	leanCosine: number
): vector
	local x: number, y: number, z: number = at.x, at.y, at.z

	if y > waist then
		local up: number = y - waist
		x, y = x * leanCosine + up * leanSine, waist - x * leanSine + up * leanCosine
	end

	return vector.create(feet.x + cosine * x + sine * z, feet.y + y, feet.z - sine * x + cosine * z)
end

local function place(
	from: Shape,
	into: Shape,
	feet: vector,
	sine: number,
	cosine: number,
	waist: number,
	leanSine: number,
	leanCosine: number
)
	into.from = point(from.from, feet, sine, cosine, waist, leanSine, leanCosine)
	into.to = point(from.to, feet, sine, cosine, waist, leanSine, leanCosine)
	into.radius = from.radius
end

--[[
    Fills a slot's Sample from a sample's values, with the posture's shapes
    placed: the word's posture, Crouch while it swims, and Downed for a
    lying sample

    @ yawSteps | the yaw in the u16's steps of the turn
--]]

local function fill(
	slot: number,
	position: vector,
	platform: number,
	yawSteps: number,
	word: number,
	lean: number,
	epoch: number,
	lying: boolean
): Sample
	StateWord.unpack(word, Scratch)

	local posture: Posture = Scratch.posture
	if lying then
		posture = "Downed"
	elseif Scratch.mode == "Swim" then
		posture = "Crouch"
	end

	local sample: Sample = sampleFor(slot)
	local placed: Placed = PlacedShapes[slot][posture]
	local shapes: Shapes = Postures[posture]

	local yaw: number = (yawSteps % ANGLE_STEPS) / YAW_SCALE
	local sine: number = Math.sin(yaw)
	local cosine: number = Math.cos(yaw)
	local leanSine: number = Math.sin(lean * DEGREES)
	local leanCosine: number = Math.cos(lean * DEGREES)

	place(shapes.body, placed.body, position, sine, cosine, shapes.waist, leanSine, leanCosine)

	for name: string, shape: Shape in shapes.zones do
		place(shape, placed.zones[name], position, sine, cosine, shapes.waist, leanSine, leanCosine)
	end

	sample.epoch = epoch
	sample.position = position
	sample.platform = platform
	sample.yaw = yaw
	sample.posture = posture
	sample.body = placed.body
	sample.zones = placed.zones

	return sample
end

-- A slot's Sample from the one sample at a tick, nil for a tick spent in Noclip or Parked
local function answer(slot: number, data: buffer, tick: number): Sample?
	local offset: number = entry(data, tick)
	if absent(data, offset) then
		return nil
	end

	local position: vector, xTop: number, zTop: number = Record.readPosition(data, offset + POSITION_AT)

	return fill(
		slot,
		position,
		platformOf(xTop, zTop),
		buffer.readu16(data, offset + YAW_AT),
		buffer.readu16(data, offset + WORD_AT),
		leanOf(data, offset),
		buffer.readu8(data, offset + EPOCH_AT),
		bit32.btest(buffer.readu8(data, offset + FLAGS_AT), LYING)
	)
end

--[[
    A slot's Sample between the samples at a tick and the next, nil when
    either was spent in Noclip or Parked. Position and lean go through
    Math.lerp, yaw on the shortest arc, and the earlier sample's posture
    holds until the next one's tick. An epoch change or a platform boarded
    or left between them takes effect at the next tick, so until then the
    earlier sample answers, held and never interpolated across
--]]

local function between(slot: number, data: buffer, tick: number, fraction: number): Sample?
	local first: number = entry(data, tick)
	local second: number = entry(data, tick + 1)
	if absent(data, first) or absent(data, second) then
		return nil
	end

	local epoch: number = buffer.readu8(data, first + EPOCH_AT)
	if buffer.readu8(data, second + EPOCH_AT) ~= epoch then
		return answer(slot, data, tick)
	end

	local from: vector, fromX: number, fromZ: number = Record.readPosition(data, first + POSITION_AT)
	local to: vector, toX: number, toZ: number = Record.readPosition(data, second + POSITION_AT)
	local platform: number = platformOf(fromX, fromZ)
	if platformOf(toX, toZ) ~= platform then
		return answer(slot, data, tick)
	end

	local position: vector = vector.create(
		Math.lerp(from.x, to.x, fraction),
		Math.lerp(from.y, to.y, fraction),
		Math.lerp(from.z, to.z, fraction)
	)

	local yawFrom: number = buffer.readu16(data, first + YAW_AT)
	local yawTo: number = buffer.readu16(data, second + YAW_AT)
	local yaw: number = Math.lerp(yawFrom, yawFrom + Sequence.difference(yawTo, yawFrom), fraction)
	local lean: number = Math.lerp(leanOf(data, first), leanOf(data, second), fraction)
	local lying: boolean = bit32.btest(buffer.readu8(data, first + FLAGS_AT), LYING)

	return fill(slot, position, platform, yaw, buffer.readu16(data, first + WORD_AT), lean, epoch, lying)
end

--[[
    A slot's state at a render time in relay ticks with its fraction, its
    hit shapes placed, or nil for a time the history no longer holds or one
    spent in Noclip or Parked. A time before an epoch change's tick answers
    the sample on its own side, held, and a time past the slot's newest
    sample answers that sample, never extrapolated. The Sample is the
    slot's own table, which the next read for it rewrites

    @ renderTime | relay ticks as the server counts them, unwrapped
--]]

function History.sampleAt(slot: number, renderTime: number): Sample?
	if not Started then
		error("History.sampleAt ran before History.start", 2)
	elseif not Slots.valid(slot) then
		error(`History.sampleAt takes a slot from 0 to {SLOTS - 1}, not {slot}`, 2)
	elseif not isFinite(renderTime) then
		error(`History.sampleAt takes the render time as a finite number of relay ticks, not {renderTime}`, 2)
	end

	local newest: number? = Newest[slot]
	local present: number? = Present
	if newest == nil or present == nil then
		return nil
	end

	-- The ring reaches the history's length back from the newest tick any body wrote
	if renderTime < math.max(Oldest[slot], present - Capacity + 1) then
		return nil
	end

	local data: buffer = Buffers[slot]
	local tick: number = math.floor(renderTime)
	local fraction: number = renderTime - tick

	if tick >= newest then
		return answer(slot, data, newest)
	elseif fraction == 0 then
		return answer(slot, data, tick)
	end

	return between(slot, data, tick, fraction)
end

--[[
    The render time a shot rewinds to in relay ticks, whether its claimed
    render time was inside the band, and the claim's offset from the
    expected time, which a band report carries. The expected time is the
    command's tick less the RTT, its capped queue wait and the clamped
    delay; a claim inside the band is used as claimed, and one outside
    gives way to the expected time. The result is then held inside the
    rewind's cap and the history, never later than the command's tick or
    the newest sample. A simulation tick falls at relay tick tick * relay /
    simulation

    @ tick | the simulation tick the shot's command ran on
    @ rtt | the connection's smoothed round trip, seconds
    @ jitter | that round trip's standard deviation, seconds
    @ wait | the simulation ticks the command waited in the queue
    @ delay | the client's reported interpolation delay, seconds
    @ renderTime | the claimed render time in relay ticks, its whole ticks full or their low 16 bits
--]]

function History.rewindFor(
	tick: number,
	rtt: number,
	jitter: number,
	wait: number,
	delay: number,
	renderTime: number
): (number, boolean, number)
	if not Started then
		error("History.rewindFor ran before History.start", 2)
	elseif not isWhole(tick) then
		error(`History.rewindFor takes the command's tick as a whole number of 0 or more, not {tick}`, 2)
	elseif not isFinite(renderTime) then
		error(`History.rewindFor takes the claimed render time as a finite number, not {renderTime}`, 2)
	elseif not (isTerm(rtt) and isTerm(jitter) and isTerm(wait) and isTerm(delay)) then
		error(
			`History.rewindFor takes rtt, jitter, wait and delay of 0 or more, not {rtt}, {jitter}, {wait}, {delay}`,
			2
		)
	end

	local now: number = tick * RelayRate / SimulationRate
	local queued: number = math.min(wait, QueueWait) / SimulationRate
	local delayed: number = math.clamp(delay, DelayMin, DelayMax)
	local expected: number = now - (rtt + queued + delayed) * RelayRate

	-- The claim's whole ticks unwrapped against the command's, so the low 16 bits of a shot field read as the full tick
	local base: number = math.floor(now)
	local whole: number = math.floor(renderTime)
	local claimed: number = base + Sequence.difference(whole % TICK_WRAP, base % TICK_WRAP) + (renderTime - whole)

	local width: number = math.min(Band + BandSigmas * jitter * RelayRate, BandMax)
	local offset: number = claimed - expected
	local inside: boolean = math.abs(offset) <= width
	local chosen: number = inside and claimed or expected

	-- The cap wins over the newest sample, which a read past it answers anyway
	local reach: number = math.min(Ceiling * RelayRate, (math.min(rtt, RttCap) + queued + delayed) * RelayRate + Extra)
	local earliest: number = now - reach
	local latest: number = now

	local present: number? = Present
	if present then
		earliest = math.max(earliest, present - Capacity + 1)
		latest = math.min(latest, present)
	end

	return math.max(math.min(chosen, latest), earliest), inside, offset
end

return History
