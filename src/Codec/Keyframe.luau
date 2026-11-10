--[[
    The keyframe a clip ring starts from: a viewer's current view as one
    buffer, every character it is sent with its kind, newest record, look and
    held item, every called platform's latest press, and its own character
--]]

--!strict
local Block = require(script.Parent.Block)
local Constants = require(script.Parent.Parent.Constants)

local WITHHELD_AT: number = 7 -- The kind byte's top bit, marking a character withheld from a spectated target
local ID_BYTES: number = 2 -- The own character's slot and generation, 0 for none
local OWN_BYTES: number = ID_BYTES + 2 * Constants.PREFIX_BYTES -- Its id and the lengths of its look and held item
local WRAP: number = 2 ^ 16

type Kind = Block.Kind

export type Character = {
	kind: Kind,
	withheld: boolean, -- Withheld from the spectated target, and sent to its moderator alone
	record: buffer, -- Its newest record, 16 B
	look: buffer, -- The game's slot-table fields, packed
	held: buffer, -- The game's held-item fields, packed, and empty when nothing is held
}

export type Platform = {
	id: number,
	tick: number, -- Its latest press's server tick, a u32
}

-- The view's own character, which the relay never lists among those it sends: a spectating moderator's is its target's
export type Own = {
	id: number, -- Its slot plus its generation times 4,096
	look: buffer, -- Empty while none is set for its life
	held: buffer, -- Empty while nothing is held
}

export type Keyframe = {
	hash: number, -- The declarations' hash, which names how its game fields are packed
	tick: number, -- The relay tick it samples
	sequence: number, -- The viewer's newest message sequence
	characters: { Character },
	platforms: { Platform },
	own: Own?, -- Nil while the view has no character of its own
}

local Keyframe = {}

local function writePart(data: buffer, offset: number, part: buffer): number
	buffer.writeu8(data, offset, buffer.len(part))
	buffer.copy(data, offset + Constants.PREFIX_BYTES, part)

	return offset + Constants.PREFIX_BYTES + buffer.len(part)
end

--[[
    Writes a keyframe into a new buffer of its exact length, stamped with
    CODEC_VERSION, erroring on a part past its bound, more characters or
    platforms than its counts hold, or an own character's id outside 1 to
    65,535, since 0 means none
--]]

function Keyframe.write(keyframe: Keyframe): buffer
	local own: Own? = keyframe.own
	local ownLook: buffer = own and own.look or buffer.create(0)
	local ownHeld: buffer = own and own.held or buffer.create(0)
	local lookLength: number = buffer.len(ownLook)
	local heldLength: number = buffer.len(ownHeld)

	if own and not (own.id >= 1 and own.id < WRAP and own.id % 1 == 0) then
		error(`A keyframe's own character's id is 1 to {WRAP - 1}, not {own.id}`)
	elseif lookLength > Constants.MAX_LOOK or heldLength > Constants.MAX_HELD then
		error(`A keyframe's own look of {lookLength} B or held item of {heldLength} B passes its bound`)
	end

	local bytes: number = Constants.KEYFRAME_HEADER_BYTES
		+ Constants.PREFIX_BYTES
		+ #keyframe.platforms * Constants.KEYFRAME_PLATFORM_BYTES
		+ OWN_BYTES
		+ lookLength
		+ heldLength

	for _, character: Character in keyframe.characters do
		local look: number = buffer.len(character.look)
		local held: number = buffer.len(character.held)

		if buffer.len(character.record) ~= Constants.RECORD_BYTES then
			error(`A keyframe's character record is {Constants.RECORD_BYTES} B, not {buffer.len(character.record)}`)
		elseif look > Constants.MAX_LOOK or held > Constants.MAX_HELD then
			error(`A keyframe's look of {look} B or held item of {held} B passes its bound`)
		end

		bytes += Constants.KEYFRAME_CHARACTER_BYTES + look + held
	end

	if #keyframe.characters > Constants.SLOTS or #keyframe.platforms > Constants.MAX_PLATFORMS then
		error(`A keyframe holds at most {Constants.SLOTS} characters and {Constants.MAX_PLATFORMS} platforms`)
	end

	local data: buffer = buffer.create(bytes)
	buffer.writeu16(data, 0, Constants.CODEC_VERSION)
	buffer.writeu32(data, 2, keyframe.hash)
	buffer.writeu16(data, 6, keyframe.tick)
	buffer.writeu16(data, 8, keyframe.sequence)
	buffer.writeu16(data, 10, #keyframe.characters)

	local offset: number = Constants.KEYFRAME_HEADER_BYTES
	for _, character: Character in keyframe.characters do
		local kind: number? = table.find(Block.KINDS, character.kind)
		if not kind then
			error(`A keyframe's character is a Player, Npc, Body or Sleeper, not {character.kind}`)
		end

		local code: number = kind - 1
		if character.withheld then
			code = bit32.replace(code, 1, WITHHELD_AT)
		end

		buffer.writeu8(data, offset, code)
		buffer.copy(data, offset + 1, character.record)
		offset = writePart(data, offset + 1 + Constants.RECORD_BYTES, character.look)
		offset = writePart(data, offset, character.held)
	end

	buffer.writeu8(data, offset, #keyframe.platforms)
	offset += Constants.PREFIX_BYTES

	for _, platform: Platform in keyframe.platforms do
		if not (platform.id >= 1 and platform.id <= Constants.MAX_PLATFORMS and platform.id % 1 == 0) then
			error(`A keyframe's platform id is 1 to {Constants.MAX_PLATFORMS}, not {platform.id}`)
		end

		buffer.writeu8(data, offset, platform.id)
		buffer.writeu32(data, offset + 1, platform.tick)
		offset += Constants.KEYFRAME_PLATFORM_BYTES
	end

	buffer.writeu16(data, offset, own and own.id or 0)
	offset = writePart(data, offset + ID_BYTES, ownLook)
	writePart(data, offset, ownHeld)

	return data
end

-- Errors when bytes more from offset pass a keyframe's length
local function within(offset: number, bytes: number, length: number)
	if offset + bytes > length then
		error(`A keyframe of {length} B ends inside the part at byte {offset}`)
	end
end

-- Copies the part behind the length at offset out of data, and gives it and the offset after it
local function readPart(data: buffer, offset: number, length: number, bound: number): (buffer, number)
	within(offset, Constants.PREFIX_BYTES, length)

	local bytes: number = buffer.readu8(data, offset)
	if bytes > bound then
		error(`A keyframe's part of {bytes} B passes its {bound} B`)
	end

	within(offset + Constants.PREFIX_BYTES, bytes, length)

	local part: buffer = buffer.create(bytes)
	buffer.copy(part, 0, data, offset + Constants.PREFIX_BYTES, bytes)

	return part, offset + Constants.PREFIX_BYTES + bytes
end

--[[
    Reads a keyframe into new tables, erroring on one stamped with another
    CODEC_VERSION, since its layouts are another version's, and on bytes
    that aren't a keyframe
--]]

function Keyframe.read(data: buffer): Keyframe
	local length: number = buffer.len(data)
	within(0, Constants.KEYFRAME_HEADER_BYTES, length)

	local version: number = buffer.readu16(data, 0)
	if version ~= Constants.CODEC_VERSION then
		error(`A keyframe of CODEC_VERSION {version} is read only by that version's decoder`)
	end

	local keyframe: Keyframe = {
		hash = buffer.readu32(data, 2),
		tick = buffer.readu16(data, 6),
		sequence = buffer.readu16(data, 8),
		characters = {},
		platforms = {},
	}

	local offset: number = Constants.KEYFRAME_HEADER_BYTES
	for _ = 1, buffer.readu16(data, 10) do
		within(offset, 1 + Constants.RECORD_BYTES, length)

		local code: number = buffer.readu8(data, offset)
		local kind: Kind? = Block.KINDS[bit32.extract(code, 0, WITHHELD_AT) + 1]
		if not kind then
			error(`A keyframe's kind code {code} has no kind`)
		end

		local record: buffer = buffer.create(Constants.RECORD_BYTES)
		buffer.copy(record, 0, data, offset + 1, Constants.RECORD_BYTES)

		local look: buffer, held: buffer
		look, offset = readPart(data, offset + 1 + Constants.RECORD_BYTES, length, Constants.MAX_LOOK)
		held, offset = readPart(data, offset, length, Constants.MAX_HELD)

		table.insert(keyframe.characters, {
			kind = kind,
			withheld = bit32.extract(code, WITHHELD_AT) == 1,
			record = record,
			look = look,
			held = held,
		})
	end

	within(offset, Constants.PREFIX_BYTES, length)

	local platforms: number = buffer.readu8(data, offset)
	offset += Constants.PREFIX_BYTES
	within(offset, platforms * Constants.KEYFRAME_PLATFORM_BYTES + OWN_BYTES, length)

	for _ = 1, platforms do
		table.insert(keyframe.platforms, {
			id = buffer.readu8(data, offset),
			tick = buffer.readu32(data, offset + 1),
		})
		offset += Constants.KEYFRAME_PLATFORM_BYTES
	end

	local id: number = buffer.readu16(data, offset)
	local look: buffer, held: buffer
	look, offset = readPart(data, offset + ID_BYTES, length, Constants.MAX_LOOK)
	held, offset = readPart(data, offset, length, Constants.MAX_HELD)

	if id ~= 0 then
		keyframe.own = { id = id, look = look, held = held }
	elseif buffer.len(look) > 0 or buffer.len(held) > 0 then
		error("A keyframe with no own character carries a look or a held item for it")
	end

	if offset ~= length then
		error(`A keyframe of {length} B carries {length - offset} B past its own character`)
	end

	return keyframe
end

return Keyframe
