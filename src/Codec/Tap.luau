--[[
    The recording taps' layouts: the frame a sink is handed each relay tick,
    its blocks as sent with each record's send reason, the owner's OwnerState,
    view lag and looks, and the snapshot of every taken slot's look and item
--]]

--!strict
--!native
local Bits = require(script.Parent.Bits)
local Block = require(script.Parent.Block)
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)
local Feed = require(script.Parent.Feed)
local Record = require(script.Parent.Record)
local State = require(script.Parent.Parent.Step.State)

local PREFIX_BYTES: number = Constants.PREFIX_BYTES
local REASON_BITS: number = 3 -- Each record's send reason, so a frame names at most 8
local BYTE_BITS: number = 8
local WRAP: number = 2 ^ 16 -- A frame's relay tick and its counts are u16
local LENGTH_BYTES: number = 2 -- The u16 length in front of each block a frame carries
local FRAME_HEADER_BYTES: number = 4 -- A frame's relay tick and its count of blocks
local ID_BYTES: number = 2 -- A character's slot and generation, the u16 every layout names it by
local LAG_BYTES: number = 2 -- The owner's view lag in milliseconds, a u16
local SNAPSHOT_HEADER_BYTES: number = 8 -- A snapshot's CODEC_VERSION u16, declarations' hash u32 and count u16
local SNAPSHOT_ENTRY_BYTES: number = ID_BYTES + 2 + 2 * PREFIX_BYTES -- Its id, kind and rig, and both prefixes

-- Head offsets read back as shares of the game's cone, from -1 to 1, when a read is handed no limits
local SHARES: Command.Limits = { lean = 1, headCone = 1 }
local NO_LOOKS: { State.Command } = {}

-- Each send reason and rig mode by its code from 0, its place in its list
local REASONS: { Reason } = { "Clear", "Hold", "FailOpen", "Teammate", "Npc", "Hidden", "Untested" }
local RIGS: { Rig } = { "A", "B" }

local CODES: { [string]: number } = {}
for index: number, reason: Reason in REASONS do
	CODES[reason] = index - 1
end

type Kind = Block.Kind
type Limits = Command.Limits
type Look = Feed.Look

-- Why the relay sent a record, or for a withheld record why anti-ESP held it back from the target
export type Reason = "Clear" | "Hold" | "FailOpen" | "Teammate" | "Npc" | "Hidden" | "Untested"

export type Rig = "A" | "B"

-- One block a frame carries: its bytes as the relay sent them, and each of its records' send reasons in order
export type Part = {
	data: buffer,
	reasons: { Reason },
}

-- A frame's OwnerState as read, with the character it is for, the viewer's view lag and the looks it stepped
export type Owner = {
	id: number,
	data: buffer,
	lag: number, -- Milliseconds
	looks: { Look }, -- Newest first, as the feed reads them
}

-- A frame as read: the relay tick its blocks sample, its blocks, and the owner's part
export type Frame = {
	tick: number,
	blocks: { Part },
	owner: Owner?,
}

-- One taken slot as a snapshot holds it, its look empty while none is set and its held item while nothing is held
export type Entry = {
	slot: number,
	generation: number,
	kind: Kind,
	rig: Rig,
	look: buffer,
	held: buffer,
}

export type Snapshot = {
	hash: number, -- The declarations' hash, which names how the looks and held items are packed
	slots: { Entry },
}

-- The cursors the reasons are packed and read through, aimed again for each block
local Writer: Bits.Cursor = Bits.writer(buffer.create(0), 0, 0)
local Reader: Bits.Cursor = Bits.reader(buffer.create(0), 0, 0)

local Tap = {
	REASONS = REASONS, -- The send reasons by code from 1, the code a frame carries plus 1
}

-- A copy of length bytes of data from at
local function slice(data: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, data, at, length)

	return part
end

-- Errors when bytes more from offset pass a layout's length
local function within(offset: number, bytes: number, length: number, what: string)
	if offset + bytes > length then
		error(`A {what} of {length} B ends inside the part at byte {offset}`)
	end
end

--[[
    The whole bytes the send reasons of a block's records fill, 3 bits a
    record, the last byte padded with zeros
--]]

function Tap.reasonBytes(records: number): number
	return (records * REASON_BITS + BYTE_BITS - 1) // BYTE_BITS
end

--[[
    The bytes one block takes in a frame's body: its length, its bytes and
    its records' send reasons
--]]

function Tap.blockBytes(length: number, records: number): number
	return LENGTH_BYTES + length + Tap.reasonBytes(records)
end

--[[
    Writes one block into a frame's body at offset, its length, its bytes
    as the relay sent them, then the send reasons of its records records,
    3 bits each from the low bit, and gives the offset after it. Room for it
    is the caller's
--]]

function Tap.writeBlock(into: buffer, offset: number, block: buffer, reasons: { Reason }, records: number): number
	local length: number = buffer.len(block)
	if not (length >= Constants.RELAY_HEADER_BYTES and length <= Constants.MAX_RELAY_BYTES) then
		error(`A frame's block is {Constants.RELAY_HEADER_BYTES} to {Constants.MAX_RELAY_BYTES} B, not {length}`)
	end

	buffer.writeu16(into, offset, length)
	buffer.copy(into, offset + LENGTH_BYTES, block)

	local at: number = offset + LENGTH_BYTES + length
	local bytes: number = Tap.reasonBytes(records)
	local cursor: Bits.Cursor = Bits.writer(into, at, bytes, Writer)

	for index: number = 1, records do
		local code: number? = CODES[reasons[index]]
		if code == nil then
			error(`A record's send reason is one of the {#REASONS} a frame names, not {reasons[index]}`)
		end

		Bits.write(cursor, code, REASON_BITS)
	end

	return at + bytes
end

--[[
    A frame in a new buffer of its exact length: the relay tick and the
    count of blocks, the body the blocks were written into, then the
    OwnerState's length, and when there is one the id of the character it
    is for, its bytes, the view lag and the looks of the first count
    commands as the feed packs them. Lag and looks go only with an
    OwnerState, a lag left out is 0 and looks left out are none

    @ lag | the viewer's view lag in whole milliseconds, a u16
    @ limits | the game's lean and cone limits, which looks need
--]]

function Tap.frame(
	tick: number,
	blocks: number,
	body: buffer,
	length: number,
	owner: buffer?,
	ownerLength: number,
	id: number,
	lag: number?,
	looks: { State.Command }?,
	count: number?,
	limits: Limits?
): buffer
	local lagged: number = lag or 0
	local stepped: number = count or 0

	if not (blocks >= 0 and blocks < WRAP) then
		error(`A frame carries at most {WRAP - 1} blocks, not {blocks}`)
	elseif not (ownerLength >= 0 and ownerLength <= Constants.MAX_OWNER_STATE) then
		error(`A frame's OwnerState is 0 to {Constants.MAX_OWNER_STATE} B, not {ownerLength}`)
	elseif not (lagged >= 0 and lagged < WRAP and lagged % 1 == 0) then
		error(`A frame's view lag is a whole 0 to {WRAP - 1} ms, not {lagged}`)
	elseif ownerLength > 0 and stepped > 0 and not (looks and limits) then
		error(`A frame's {stepped} looks need their commands and the game's limits`)
	end

	local bytes: number = FRAME_HEADER_BYTES + length + PREFIX_BYTES
	if ownerLength > 0 then
		bytes += ID_BYTES + ownerLength + LAG_BYTES + PREFIX_BYTES + stepped * Constants.FEED_LOOK_BYTES
	end

	local data: buffer = buffer.create(bytes)
	buffer.writeu16(data, 0, tick % WRAP)
	buffer.writeu16(data, 2, blocks)
	buffer.copy(data, FRAME_HEADER_BYTES, body, 0, length)

	local at: number = FRAME_HEADER_BYTES + length
	buffer.writeu8(data, at, ownerLength)

	if owner and ownerLength > 0 then
		at += PREFIX_BYTES
		buffer.writeu16(data, at, id)
		buffer.copy(data, at + ID_BYTES, owner, 0, ownerLength)

		at += ID_BYTES + ownerLength
		buffer.writeu16(data, at, lagged)
		Feed.writeLooks(data, at + LAG_BYTES, looks or NO_LOOKS, stepped, limits or SHARES)
	end

	return data
end

--[[
    Reads a frame into new tables, each block copied out with its reasons
    and the owner's looks read with the limits given, as shares of them
    without, erroring on bytes that aren't a frame: a block that isn't one,
    a reason code no reason is given, padding other than zeros, a look list
    past a Move's or its bytes, or bytes left over
--]]

function Tap.read(data: buffer, limits: Limits?): Frame
	local length: number = buffer.len(data)
	within(0, FRAME_HEADER_BYTES, length, "frame")

	local frame: Frame = { tick = buffer.readu16(data, 0), blocks = {}, owner = nil }
	local read: Block.Block = Block.new()
	local offset: number = FRAME_HEADER_BYTES

	for _ = 1, buffer.readu16(data, 2) do
		within(offset, LENGTH_BYTES, length, "frame")

		local size: number = buffer.readu16(data, offset)
		within(offset + LENGTH_BYTES, size, length, "frame")

		local block: buffer = slice(data, offset + LENGTH_BYTES, size)
		Block.read(block, read)

		local records: number = read.recordCount
		local at: number = offset + LENGTH_BYTES + size
		local bytes: number = Tap.reasonBytes(records)
		within(at, bytes, length, "frame")

		local cursor: Bits.Cursor = Bits.reader(data, at, bytes, Reader)
		local reasons: { Reason } = {}

		for index: number = 1, records do
			local code: number? = Bits.read(cursor, REASON_BITS)
			local reason: Reason? = code and REASONS[code + 1]
			if not reason then
				error(`A frame's send reason code {code} has no reason`)
			end

			reasons[index] = reason
		end

		local padding: number = bytes * BYTE_BITS - records * REASON_BITS
		if padding > 0 and Bits.read(cursor, padding) ~= 0 then
			error("A frame's send reasons pad their last byte with bits other than 0")
		end

		table.insert(frame.blocks, { data = block, reasons = reasons })
		offset = at + bytes
	end

	within(offset, PREFIX_BYTES, length, "frame")

	local ownerLength: number = buffer.readu8(data, offset)
	offset += PREFIX_BYTES

	if ownerLength > 0 then
		within(offset, ID_BYTES + ownerLength + LAG_BYTES + PREFIX_BYTES, length, "frame")

		local id: number = buffer.readu16(data, offset)
		local owner: buffer = slice(data, offset + ID_BYTES, ownerLength)
		offset += ID_BYTES + ownerLength

		local lag: number = buffer.readu16(data, offset)
		local looks: { Look } = {}
		local _: number, after: number = Feed.readLooks(data, offset + LAG_BYTES, length, looks, limits or SHARES)

		frame.owner = { id = id, data = owner, lag = lag, looks = looks }
		offset = after
	end

	if offset ~= length then
		error(`A frame of {length} B carries {length - offset} B past its OwnerState`)
	end

	return frame
end

-- Writes a part behind its u8 length at offset, and gives the offset after it
local function writePart(data: buffer, offset: number, part: buffer): number
	buffer.writeu8(data, offset, buffer.len(part))
	buffer.copy(data, offset + PREFIX_BYTES, part)

	return offset + PREFIX_BYTES + buffer.len(part)
end

--[[
    Writes a snapshot into a new buffer of its exact length, stamped with
    CODEC_VERSION, erroring on a kind or rig no code is given, a part past
    its bound or more slots than the slot table holds
--]]

function Tap.writeSnapshot(snapshot: Snapshot): buffer
	local slots: { Entry } = snapshot.slots
	if #slots > Constants.SLOTS then
		error(`A snapshot holds at most {Constants.SLOTS} slots, not {#slots}`)
	end

	local bytes: number = SNAPSHOT_HEADER_BYTES
	for _, entry: Entry in slots do
		local look: number = buffer.len(entry.look)
		local held: number = buffer.len(entry.held)
		if look > Constants.MAX_LOOK or held > Constants.MAX_HELD then
			error(`A snapshot's look of {look} B or held item of {held} B passes its bound`)
		end

		bytes += SNAPSHOT_ENTRY_BYTES + look + held
	end

	local data: buffer = buffer.create(bytes)
	buffer.writeu16(data, 0, Constants.CODEC_VERSION)
	buffer.writeu32(data, 2, snapshot.hash)
	buffer.writeu16(data, 6, #slots)

	local offset: number = SNAPSHOT_HEADER_BYTES
	for _, entry: Entry in slots do
		local kind: number? = table.find(Block.KINDS, entry.kind)
		local rig: number? = table.find(RIGS, entry.rig)
		if not kind or not rig then
			error(`A snapshot's slot is a Player, Npc, Body or Sleeper on rig A or B, not {entry.kind} on {entry.rig}`)
		end

		buffer.writeu16(data, offset, Record.id(entry.slot, entry.generation))
		buffer.writeu8(data, offset + ID_BYTES, kind - 1)
		buffer.writeu8(data, offset + ID_BYTES + 1, rig - 1)

		offset = writePart(data, offset + ID_BYTES + 2, entry.look)
		offset = writePart(data, offset, entry.held)
	end

	return data
end

-- Copies the part behind the length at offset out of a snapshot, and gives it and the offset after it
local function readPart(data: buffer, offset: number, length: number, bound: number): (buffer, number)
	within(offset, PREFIX_BYTES, length, "snapshot")

	local bytes: number = buffer.readu8(data, offset)
	if bytes > bound then
		error(`A snapshot's part of {bytes} B passes its {bound} B`)
	end

	within(offset + PREFIX_BYTES, bytes, length, "snapshot")

	return slice(data, offset + PREFIX_BYTES, bytes), offset + PREFIX_BYTES + bytes
end

--[[
    Reads a snapshot into new tables, erroring on one stamped with another
    CODEC_VERSION and on bytes that aren't a snapshot
--]]

function Tap.readSnapshot(data: buffer): Snapshot
	local length: number = buffer.len(data)
	within(0, SNAPSHOT_HEADER_BYTES, length, "snapshot")

	local version: number = buffer.readu16(data, 0)
	if version ~= Constants.CODEC_VERSION then
		error(`A snapshot of CODEC_VERSION {version} is read only by that version's decoder`)
	end

	local snapshot: Snapshot = { hash = buffer.readu32(data, 2), slots = {} }
	local offset: number = SNAPSHOT_HEADER_BYTES

	for _ = 1, buffer.readu16(data, 6) do
		within(offset, ID_BYTES + 2, length, "snapshot")

		local slot: number, generation: number = Record.split(buffer.readu16(data, offset))
		local kindCode: number = buffer.readu8(data, offset + ID_BYTES)
		local rigCode: number = buffer.readu8(data, offset + ID_BYTES + 1)
		local kind: Kind? = Block.KINDS[kindCode + 1]
		local rig: Rig? = RIGS[rigCode + 1]
		if not kind or not rig then
			error(`A snapshot's kind code {kindCode} or rig code {rigCode} has no value`)
		end

		local look: buffer, held: buffer
		look, offset = readPart(data, offset + ID_BYTES + 2, length, Constants.MAX_LOOK)
		held, offset = readPart(data, offset, length, Constants.MAX_HELD)

		table.insert(snapshot.slots, {
			slot = slot,
			generation = generation,
			kind = kind,
			rig = rig,
			look = look,
			held = held,
		})
	end

	if offset ~= length then
		error(`A snapshot of {length} B carries {length - offset} B past its last slot`)
	end

	return snapshot
end

return Tap
