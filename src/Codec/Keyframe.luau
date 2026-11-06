--[[
    The keyframe a clip ring starts from: a viewer's current view as one
    buffer, every character it is sent with its kind, newest record, look and
    held item, and every called platform's latest press
--]]

--!strict
local Block = require(script.Parent.Block)
local Constants = require(script.Parent.Parent.Constants)

local WITHHELD_AT: number = 7 -- The kind byte's top bit, marking a character withheld from a spectated target

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

export type Keyframe = {
	hash: number, -- The declarations' hash, which names how its game fields are packed
	tick: number, -- The relay tick it samples
	sequence: number, -- The viewer's newest message sequence
	characters: { Character },
	platforms: { Platform },
}

local Keyframe = {}

local function writePart(data: buffer, offset: number, part: buffer): number
	buffer.writeu8(data, offset, buffer.len(part))
	buffer.copy(data, offset + Constants.PREFIX_BYTES, part)

	return offset + Constants.PREFIX_BYTES + buffer.len(part)
end

--[[
    Writes a keyframe into a new buffer of its exact length, stamped with
    CODEC_VERSION, erroring on a part past its bound or more characters or
    platforms than its counts hold
--]]

function Keyframe.write(keyframe: Keyframe): buffer
	local bytes: number = Constants.KEYFRAME_HEADER_BYTES
		+ Constants.PREFIX_BYTES
		+ #keyframe.platforms * Constants.KEYFRAME_PLATFORM_BYTES

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
	if offset + platforms * Constants.KEYFRAME_PLATFORM_BYTES ~= length then
		error(`A keyframe's {platforms} platforms don't end its {length} B`)
	end

	for _ = 1, platforms do
		table.insert(keyframe.platforms, {
			id = buffer.readu8(data, offset),
			tick = buffer.readu32(data, offset + 1),
		})
		offset += Constants.KEYFRAME_PLATFORM_BYTES
	end

	return keyframe
end

return Keyframe
