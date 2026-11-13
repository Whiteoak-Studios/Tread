--[[
    The pure decoder behind Tread.decode, for clips and tools: each layout
    read for its CODEC_VERSION into new tables, with every block of the
    game's fields handed back as its packed bytes
--]]

--!strict
local Block = require(script.Parent.Block)
local Change = require(script.Parent.Change)
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)
local Feed = require(script.Parent.Feed)
local Keyframe = require(script.Parent.Keyframe)
local OwnerState = require(script.Parent.OwnerState)
local Record = require(script.Parent.Record)
local State = require(script.Parent.Parent.Step.State)
local StateWord = require(script.Parent.StateWord)
local Tap = require(script.Parent.Tap)

-- Lean and the head offset come back as shares of the game's limits, from -1 to 1, since a decoder isn't given them
local SHARES: Command.Limits = { lean = 1, headCone = 1 }
local WIRE_COMMAND_BYTES: number = Constants.COMMAND_BYTES + Constants.PREFIX_BYTES -- Before its game fields

-- A change record's fields in the record's units, as Record reads them
local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi)
local PITCH_SCALE: number = Constants.RECORD_PITCH_STEPS / (math.pi / 2)
local BASE_AT: number = 2 -- A change's base and mask, after its slot and generation
local MASK_AT: number = 3

type Decoded = { [string]: any }
type Reader = (data: buffer) -> Decoded

local Decode = {}

-- A copy of length bytes of data from at
local function slice(data: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, data, at, length)

	return part
end

local function word(packed: number): StateWord.Word
	local unpacked: StateWord.Word = {
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
	StateWord.unpack(packed, unpacked)

	return unpacked
end

local function readRecord(data: buffer, offset: number): Decoded
	local record: Record.Record = Record.new()
	Record.read(data, offset, record, SHARES)

	local unpacked: StateWord.Word = word(record.word)

	return {
		slot = record.slot,
		generation = record.generation,
		position = record.position,
		platform = record.platform,
		yaw = record.yaw,
		pitch = record.pitch,
		lean = record.lean,
		headYaw = record.headYaw,
		headPitch = record.headPitch,
		mode = unpacked.mode,
		posture = unpacked.posture,
		sprint = unpacked.sprint,
		aim = unpacked.aim,
		waterLevel = unpacked.waterLevel,
		jumps = unpacked.jumps,
		lands = unpacked.lands,
		heavy = unpacked.heavy,
		epoch = unpacked.epoch, -- The parity a record carries
	}
end

local function readOwner(data: buffer, offset: number, length: number): Decoded
	local state: State.State = State.new()
	OwnerState.read(data, offset, length, state, nil, SHARES)

	-- The game's two blocks behind their lengths, which OwnerState.read has checked end its bytes
	local serverAt: number = offset + Constants.OWNER_STATE_BYTES + Constants.PREFIX_BYTES
	local serverLength: number = buffer.readu8(data, serverAt - Constants.PREFIX_BYTES)
	local rulesAt: number = serverAt + serverLength + Constants.PREFIX_BYTES
	local rulesLength: number = buffer.readu8(data, rulesAt - Constants.PREFIX_BYTES)

	return {
		command = state.command,
		tick = state.tick,
		depth = state.depth,
		position = state.position,
		velocity = state.velocity,
		facing = state.facing,
		mode = state.mode,
		posture = state.posture,
		sprint = state.sprint,
		aim = state.aim,
		waterLevel = state.waterLevel,
		jumps = state.jumps,
		lands = state.lands,
		heavy = state.heavy,
		epoch = state.epoch,
		platform = state.platform,
		moveMode = state.moveMode,
		grounded = state.grounded,
		lean = state.lean,
		eyeHeight = state.eyeHeight,
		apex = state.apex,
		groundHeight = state.groundHeight,
		groundTicks = state.groundTicks,
		airTicks = state.airTicks,
		mantleTicks = state.mantleTicks,
		slideCooldown = state.slideCooldown,
		mantleRise = state.mantleRise,
		ladder = state.ladder,
		fields = slice(data, serverAt, serverLength), -- The server-set block
		block = slice(data, rulesAt, rulesLength), -- The rule-state block
	}
end

--[[
    A change record's fields as it carries them, with no baseline to rebuild
    its record from: X, Z and a Y step as differences in studs, a whole Y in
    studs, yaw and pitch in radians, the state word unpacked and the last
    byte as it is, since its meaning rides in the baseline's Z
--]]

local function readChange(data: buffer, at: number): Decoded
	local slot: number, generation: number = Record.split(buffer.readu16(data, at))
	local mask: number = buffer.readu8(data, at + MASK_AT)
	local offset: number = at + Constants.CHANGE_HEADER_BYTES
	local change: Decoded = {
		slot = slot,
		generation = generation,
		base = buffer.readu8(data, at + BASE_AT),
		mask = mask,
	}

	if bit32.btest(mask, Change.X) then
		change.dx = buffer.readi16(data, offset) * Constants.RECORD_QUANTUM
		offset += 2
	end

	if bit32.btest(mask, Change.Z) then
		change.dz = buffer.readi16(data, offset) * Constants.RECORD_QUANTUM
		offset += 2
	end

	if bit32.btest(mask, Change.Y_STEP) then
		change.dy = buffer.readi8(data, offset) * Constants.RECORD_HEIGHT_QUANTUM
		offset += 1
	elseif bit32.btest(mask, Change.Y) then
		change.y = buffer.readu16(data, offset) * Constants.RECORD_HEIGHT_QUANTUM + Constants.HEIGHT_MIN
		offset += 2
	end

	if bit32.btest(mask, Change.YAW) then
		change.yaw = buffer.readu16(data, offset) / YAW_SCALE
		offset += 2
	end

	if bit32.btest(mask, Change.PITCH) then
		change.pitch = buffer.readi8(data, offset) / PITCH_SCALE
		offset += 1
	end

	if bit32.btest(mask, Change.WORD) then
		change.word = word(buffer.readu16(data, offset))
		offset += 2
	end

	if bit32.btest(mask, Change.LAST) then
		change.last = buffer.readu8(data, offset)
	end

	return change
end

local function readBlock(data: buffer, bound: number): Decoded
	local block: Block.Block = Block.new()
	Block.read(data, block, bound)

	local reveals: { Decoded } = {}
	for index: number = 1, block.revealCount do
		local reveal: Block.Reveal = block.reveals[index]
		reveals[index] = { slot = reveal.slot, generation = reveal.generation, kind = reveal.kind }
	end

	local hides: { Decoded } = {}
	for index: number = 1, block.hideCount do
		local hide: Block.Hide = block.hides[index]
		hides[index] = { slot = hide.slot, generation = hide.generation }
	end

	local looks: { Decoded } = {}
	for index: number = 1, block.lookCount do
		local look: Block.Look = block.looks[index]
		local entry: Decoded = { slot = look.slot, generation = look.generation }

		if look.look then
			entry.look = slice(data, look.lookAt, look.lookLength)
		end

		if look.held then
			entry.held = slice(data, look.heldAt, look.heldLength)
		end

		looks[index] = entry
	end

	local footsteps: { Decoded } = {}
	for index: number = 1, block.footstepCount do
		local step: Block.Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
		Block.readFootstep(data, block.footsteps[index], step)
		footsteps[index] = { at = step.at, kind = step.kind, material = step.material }
	end

	local records: { Decoded } = {}
	for index: number = 1, block.recordCount do
		records[index] = readRecord(data, block.records[index])
	end

	local changes: { Decoded } = {}
	for index: number = 1, block.changeCount do
		changes[index] = readChange(data, block.changeOffsets[index])
	end

	return {
		sequence = block.sequence,
		tick = block.tick,
		reveals = reveals,
		hides = hides,
		looks = looks,
		footsteps = footsteps,
		records = records,
		changes = changes,
	}
end

local function readRelay(data: buffer): Decoded
	return readBlock(data, Constants.MAX_RELAY_BYTES)
end

local function readWithheld(data: buffer): Decoded
	local block: Decoded = readBlock(data, Constants.MAX_RELAY_BYTES)
	if #block.reveals > 0 or #block.hides > 0 or #block.footsteps > 0 then
		error("A withheld block carries looks and records, and no reveals, hides or footstep entries")
	elseif #block.changes > 0 then
		error("A withheld block carries whole records only, and no change records")
	end

	return block
end

local function readFeed(data: buffer): Decoded
	local feed: Feed.Feed = Feed.new()
	Feed.read(data, feed, SHARES)

	local looks: { Decoded } = {}
	for index: number = 1, feed.count do
		local look: Feed.Look = feed.looks[index]
		looks[index] = { yaw = look.yaw, pitch = look.pitch, headYaw = look.headYaw, headPitch = look.headPitch }
	end

	return {
		owner = readOwner(data, feed.ownerAt, feed.ownerLength),
		looks = looks,
	}
end

local function readKeyframe(data: buffer): Decoded
	local keyframe: Keyframe.Keyframe = Keyframe.read(data)

	local characters: { Decoded } = {}
	for index: number, character: Keyframe.Character in keyframe.characters do
		characters[index] = {
			kind = character.kind,
			withheld = character.withheld,
			record = readRecord(character.record, 0),
			look = character.look,
			held = character.held,
		}
	end

	local platforms: { Decoded } = {}
	for index: number, platform: Keyframe.Platform in keyframe.platforms do
		platforms[index] = { id = platform.id, tick = platform.tick }
	end

	-- The view's own character, which no relay block lists, nil when it has none
	local own: Decoded? = nil
	local kept: Keyframe.Own? = keyframe.own
	if kept then
		local slot: number, generation: number = Record.split(kept.id)
		own = { id = kept.id, slot = slot, generation = generation, look = kept.look, held = kept.held }
	end

	return {
		version = Constants.CODEC_VERSION,
		hash = keyframe.hash,
		tick = keyframe.tick,
		sequence = keyframe.sequence,
		characters = characters,
		platforms = platforms,
		gravity = keyframe.gravity,
		own = own,
	}
end

local function readOneRecord(data: buffer): Decoded
	if buffer.len(data) ~= Constants.RECORD_BYTES then
		error(`A record is {Constants.RECORD_BYTES} B, not {buffer.len(data)}`)
	end

	return readRecord(data, 0)
end

local function readOwnerState(data: buffer): Decoded
	return readOwner(data, 0, buffer.len(data))
end

-- One command as Move carries it: Tread's 11 B, then the game's fields behind their u8 length
local function readCommand(data: buffer): Decoded
	local length: number = buffer.len(data)
	if length < WIRE_COMMAND_BYTES then
		error(`A command is at least {WIRE_COMMAND_BYTES} B, not {length}`)
	end

	local fieldsLength: number = buffer.readu8(data, Constants.COMMAND_BYTES)
	if fieldsLength > Constants.MAX_COMMAND_FIELDS or WIRE_COMMAND_BYTES + fieldsLength ~= length then
		error(`A command's {fieldsLength} B of game fields don't end its {length} B`)
	end

	local wire: Command.Wire = {
		moveX = buffer.readi8(data, 0),
		moveZ = buffer.readi8(data, 1),
		buttons = buffer.readu16(data, 2),
		yaw = buffer.readu16(data, 4),
		pitch = buffer.readi16(data, 6),
		lean = buffer.readi8(data, 8),
		headYaw = buffer.readi8(data, 9),
		headPitch = buffer.readi8(data, 10),
		fields = slice(data, WIRE_COMMAND_BYTES, fieldsLength),
	}

	local command: State.Command = Command.new()
	Command.read(wire, command, nil, SHARES)

	return {
		forward = command.forward,
		right = command.right,
		jump = command.jump,
		crouch = command.crouch,
		sprint = command.sprint,
		aim = command.aim,
		yaw = command.yaw,
		pitch = command.pitch,
		lean = command.lean,
		headYaw = command.headYaw,
		headPitch = command.headPitch,
		fields = wire.fields,
	}
end

--[[
    A tap frame: each block decoded as a relay block, each record with its
    send reason beside its fields, and the OwnerState with the slot and
    generation of the character it is for, the view lag in milliseconds
    and the looks it stepped in the feed's shape, nil when it has none
--]]

local function readTap(data: buffer): Decoded
	local frame: Tap.Frame = Tap.read(data, SHARES)

	local blocks: { Decoded } = {}
	for index: number, part: Tap.Part in frame.blocks do
		local block: Decoded = readBlock(part.data, Constants.TAP_BLOCK_BYTES)
		for at: number, record: Decoded in block.records do
			record.reason = part.reasons[at]
		end

		blocks[index] = block
	end

	local owner: Decoded? = nil
	local kept: Tap.Owner? = frame.owner
	if kept then
		local decoded: Decoded = readOwnerState(kept.data)
		decoded.slot, decoded.generation = Record.split(kept.id)
		decoded.lag = kept.lag
		decoded.looks = kept.looks
		owner = decoded
	end

	return {
		tick = frame.tick,
		blocks = blocks,
		owner = owner,
	}
end

-- A snapshot: every taken slot with its kind, rig, look and held item, the parts as their packed bytes
local function readSnapshot(data: buffer): Decoded
	local snapshot: Tap.Snapshot = Tap.readSnapshot(data)

	local slots: { Decoded } = {}
	for index: number, entry: Tap.Entry in snapshot.slots do
		slots[index] = {
			slot = entry.slot,
			generation = entry.generation,
			kind = entry.kind,
			rig = entry.rig,
			look = entry.look,
			held = entry.held,
		}
	end

	return {
		version = Constants.CODEC_VERSION,
		hash = snapshot.hash,
		slots = slots,
	}
end

-- Each CODEC_VERSION's readers by the layout's name, the live codec's for the current version
local Readers: { [number]: { [string]: Reader } } = {
	[Constants.CODEC_VERSION] = {
		relay = readRelay,
		withheld = readWithheld,
		owner = readOwnerState,
		feed = readFeed,
		keyframe = readKeyframe,
		record = readOneRecord,
		command = readCommand,
		tap = readTap,
		snapshot = readSnapshot,
	},
}

--[[
    Decodes data as the layout kind names, relay, withheld, owner, feed,
    keyframe, record, command, tap or snapshot, as CODEC_VERSION version
    packed it. It may allocate, since nothing calls it on a hot path, and it
    errors on a version or kind it has no reader for and on bytes that
    aren't that layout
--]]

function Decode.decode(version: number, kind: string, data: buffer): { [string]: any }
	local readers: { [string]: Reader }? = Readers[version]
	if not readers then
		error(`Tread decodes CODEC_VERSION {Constants.CODEC_VERSION}, not {version}`)
	end

	local reader: Reader? = readers[kind]
	if not reader then
		local kinds: string = "relay, withheld, owner, feed, keyframe, record, command, tap and snapshot"
		error(`Tread decodes {kinds}, not {kind}`)
	elseif type(data) ~= "buffer" then
		error(`Tread decodes a buffer, not a {type(data)}`)
	end

	return reader(data)
end

return Decode
