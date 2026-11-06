--[[
    The relay block, server to viewer, at most 896 B: its header, reveal and
    kind entries, hide entries, look entries, footstep entries and records,
    and the 10 B footstep entry a culled enemy's step rides in
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local Record = require(script.Parent.Record)

local U8_TOP: number = 2 ^ 8 - 1 -- The most entries a section's u8 count holds

-- Each value's place in its list, from 0, is its code
local KINDS: { Kind } = { "Player", "Npc", "Body", "Sleeper" }
local STEPS: { Step } = { "Walk", "Sprint", "Jump", "Land" }

-- The bits of a look entry's flags byte, each saying a part is present
local LOOK_FLAG: number = 0
local HELD_FLAG: number = 1
local FLAG_BITS: number = 2

-- The kind of character a reveal marks
export type Kind = "Player" | "Npc" | "Body" | "Sleeper"

-- The kind of step a footstep entry holds
export type Step = "Walk" | "Sprint" | "Jump" | "Land"

-- A reveal-and-kind entry, which starts a stretch of a viewer being sent a character or marks its change of kind
export type Reveal = {
	slot: number,
	generation: number,
	kind: Kind,
}

-- A hide entry, which ends the stretch
export type Hide = {
	slot: number,
	generation: number,
}

-- A look entry. Each part present is a stretch of packed game fields at an offset of its data, and a held part of
-- length 0 holds nothing
export type Look = {
	slot: number,
	generation: number,
	look: boolean, -- Whether the look, the game's slot-table fields, is present
	lookData: buffer,
	lookAt: number,
	lookLength: number,
	held: boolean, -- Whether the held item, the game's held-item fields, is present
	heldData: buffer,
	heldAt: number,
	heldLength: number,
}

-- A culled enemy's step: where it fell, its kind and the ground's material, and no player
export type Footstep = {
	at: vector,
	kind: Step,
	material: Enum.Material,
}

-- One relay block's contents, each list holding at least its count. Footstep entries and records are already
-- encoded, each at an offset of its data, so a target's record is encoded once a tick and copied to every viewer
export type Block = {
	sequence: number, -- The viewer's own message sequence, which its Move acknowledges
	tick: number, -- The relay tick its records sample
	revealCount: number,
	reveals: { Reveal },
	hideCount: number,
	hides: { Hide },
	lookCount: number,
	looks: { Look },
	footstepCount: number,
	footsteps: { number },
	footstepData: buffer,
	recordCount: number,
	records: { number },
	recordData: buffer,
}

-- Each material by its Enum value, which a footstep entry carries
local Materials: { [number]: Enum.Material } = {}
for _, material: Enum.Material in Enum.Material:GetEnumItems() do
	Materials[material.Value] = material
end

local Block = {
	KINDS = KINDS, -- The kinds by code, which a reveal and a keyframe's character carry
}

--[[
    An empty block, which a writer fills and a reader reads into, each
    reusing it
--]]

function Block.new(): Block
	local empty: buffer = buffer.create(0)

	return {
		sequence = 0,
		tick = 0,
		revealCount = 0,
		reveals = {} :: { Reveal },
		hideCount = 0,
		hides = {} :: { Hide },
		lookCount = 0,
		looks = {} :: { Look },
		footstepCount = 0,
		footsteps = {} :: { number },
		footstepData = empty,
		recordCount = 0,
		records = {} :: { number },
		recordData = empty,
	}
end

-- The bytes a look entry fills, erroring on a part past the bound its declarations keep to
local function lookBytes(look: Look): number
	local bytes: number = Constants.LOOK_ENTRY_BYTES

	if look.look then
		if not (look.lookLength >= 0 and look.lookLength <= Constants.MAX_LOOK) then
			error(`A look entry's look is 0 to {Constants.MAX_LOOK} B, not {look.lookLength}`)
		end

		bytes += Constants.PREFIX_BYTES + look.lookLength
	end

	if look.held then
		if not (look.heldLength >= 0 and look.heldLength <= Constants.MAX_HELD) then
			error(`A look entry's held item is 0 to {Constants.MAX_HELD} B, not {look.heldLength}`)
		end

		bytes += Constants.PREFIX_BYTES + look.heldLength
	end

	return bytes
end

local function writePart(data: buffer, offset: number, source: buffer, at: number, length: number): number
	buffer.writeu8(data, offset, length)
	buffer.copy(data, offset + Constants.PREFIX_BYTES, source, at, length)

	return offset + Constants.PREFIX_BYTES + length
end

--[[
    Writes a block into data from its first byte and gives the bytes it
    filled, its sections in order whatever order they were filled in. It
    errors on a block past 896 B or past data, and on a section past the 255
    its count holds
--]]

function Block.write(block: Block, data: buffer): number
	local revealCount: number = block.revealCount
	local hideCount: number = block.hideCount
	local lookCount: number = block.lookCount
	local footstepCount: number = block.footstepCount
	local recordCount: number = block.recordCount

	local bytes: number = Constants.RELAY_HEADER_BYTES
		+ revealCount * Constants.REVEAL_BYTES
		+ hideCount * Constants.HIDE_BYTES
		+ footstepCount * Constants.FOOTSTEP_BYTES
		+ recordCount * Constants.RECORD_BYTES

	for index: number = 1, lookCount do
		bytes += lookBytes(block.looks[index])
	end

	if not (bytes <= Constants.MAX_RELAY_BYTES and bytes <= buffer.len(data)) then
		error(`A relay block of {bytes} B passes its {Constants.MAX_RELAY_BYTES} B or its {buffer.len(data)} B buffer`)
	elseif math.max(revealCount, hideCount, lookCount, footstepCount) > U8_TOP then
		error(`A relay block's sections hold at most {U8_TOP} entries each`)
	end

	buffer.writeu16(data, 0, block.sequence)
	buffer.writeu16(data, 2, block.tick)
	buffer.writeu8(data, 4, revealCount)
	buffer.writeu8(data, 5, hideCount)
	buffer.writeu8(data, 6, lookCount)
	buffer.writeu8(data, 7, footstepCount)

	local offset: number = Constants.RELAY_HEADER_BYTES

	for index: number = 1, revealCount do
		local reveal: Reveal = block.reveals[index]
		local kind: number? = table.find(KINDS, reveal.kind)
		if not kind then
			error(`A reveal's kind is Player, Npc, Body or Sleeper, not {reveal.kind}`)
		end

		buffer.writeu16(data, offset, Record.id(reveal.slot, reveal.generation))
		buffer.writeu8(data, offset + 2, kind - 1)
		offset += Constants.REVEAL_BYTES
	end

	for index: number = 1, hideCount do
		local hide: Hide = block.hides[index]

		buffer.writeu16(data, offset, Record.id(hide.slot, hide.generation))
		offset += Constants.HIDE_BYTES
	end

	for index: number = 1, lookCount do
		local look: Look = block.looks[index]
		local flags: number = 0

		if look.look then
			flags = bit32.replace(flags, 1, LOOK_FLAG)
		end

		if look.held then
			flags = bit32.replace(flags, 1, HELD_FLAG)
		end

		buffer.writeu16(data, offset, Record.id(look.slot, look.generation))
		buffer.writeu8(data, offset + 2, flags)
		offset += Constants.LOOK_ENTRY_BYTES

		if look.look then
			offset = writePart(data, offset, look.lookData, look.lookAt, look.lookLength)
		end

		if look.held then
			offset = writePart(data, offset, look.heldData, look.heldAt, look.heldLength)
		end
	end

	for index: number = 1, footstepCount do
		buffer.copy(data, offset, block.footstepData, block.footsteps[index], Constants.FOOTSTEP_BYTES)
		offset += Constants.FOOTSTEP_BYTES
	end

	for index: number = 1, recordCount do
		buffer.copy(data, offset, block.recordData, block.records[index], Constants.RECORD_BYTES)
		offset += Constants.RECORD_BYTES
	end

	return offset
end

-- Errors when bytes more from offset pass a block's length
local function within(offset: number, bytes: number, length: number)
	if offset + bytes > length then
		error(`A relay block of {length} B ends inside the entry at byte {offset}`)
	end
end

-- Reads the length in front of a look entry's part at offset, and gives where its bytes start and how many there are
local function readPart(data: buffer, offset: number, length: number, bound: number): (number, number)
	within(offset, Constants.PREFIX_BYTES, length)

	local bytes: number = buffer.readu8(data, offset)
	if bytes > bound then
		error(`A look entry's part of {bytes} B passes its {bound} B`)
	end

	within(offset + Constants.PREFIX_BYTES, bytes, length)

	return offset + Constants.PREFIX_BYTES, bytes
end

--[[
    Reads a block into into, reusing its entry tables. Records, footstep
    entries and look parts are left in data, at the offsets into names, so
    a reader decodes each where it lies. It errors on a block that isn't
    one: past 896 B, a section past its end, records that aren't whole, or
    a kind or flag no value is given
--]]

function Block.read(data: buffer, into: Block)
	local length: number = buffer.len(data)
	if not (length >= Constants.RELAY_HEADER_BYTES and length <= Constants.MAX_RELAY_BYTES) then
		error(`A relay block is {Constants.RELAY_HEADER_BYTES} to {Constants.MAX_RELAY_BYTES} B, not {length}`)
	end

	local revealCount: number = buffer.readu8(data, 4)
	local hideCount: number = buffer.readu8(data, 5)
	local lookCount: number = buffer.readu8(data, 6)
	local footstepCount: number = buffer.readu8(data, 7)
	local offset: number = Constants.RELAY_HEADER_BYTES

	into.sequence = buffer.readu16(data, 0)
	into.tick = buffer.readu16(data, 2)

	for index: number = 1, revealCount do
		within(offset, Constants.REVEAL_BYTES, length)

		local reveal: Reveal = into.reveals[index]
		if not reveal then
			reveal = { slot = 0, generation = 0, kind = "Player" }
			into.reveals[index] = reveal
		end

		local kind: Kind? = KINDS[buffer.readu8(data, offset + 2) + 1]
		if not kind then
			error(`A reveal's kind code {buffer.readu8(data, offset + 2)} has no kind`)
		end

		reveal.slot, reveal.generation = Record.split(buffer.readu16(data, offset))
		reveal.kind = kind
		offset += Constants.REVEAL_BYTES
	end

	for index: number = 1, hideCount do
		within(offset, Constants.HIDE_BYTES, length)

		local hide: Hide = into.hides[index]
		if not hide then
			hide = { slot = 0, generation = 0 }
			into.hides[index] = hide
		end

		hide.slot, hide.generation = Record.split(buffer.readu16(data, offset))
		offset += Constants.HIDE_BYTES
	end

	for index: number = 1, lookCount do
		within(offset, Constants.LOOK_ENTRY_BYTES, length)

		local look: Look = into.looks[index]
		if not look then
			look = {
				slot = 0,
				generation = 0,
				look = false,
				lookData = data,
				lookAt = 0,
				lookLength = 0,
				held = false,
				heldData = data,
				heldAt = 0,
				heldLength = 0,
			}
			into.looks[index] = look
		end

		local flags: number = buffer.readu8(data, offset + 2)
		if bit32.extract(flags, 0, FLAG_BITS) ~= flags then
			error(`A look entry's flags {flags} set a bit no part is given`)
		end

		look.slot, look.generation = Record.split(buffer.readu16(data, offset))
		look.look = bit32.extract(flags, LOOK_FLAG) == 1
		look.held = bit32.extract(flags, HELD_FLAG) == 1
		look.lookData = data
		look.heldData = data
		look.lookLength = 0
		look.heldLength = 0
		offset += Constants.LOOK_ENTRY_BYTES

		if look.look then
			look.lookAt, look.lookLength = readPart(data, offset, length, Constants.MAX_LOOK)
			offset = look.lookAt + look.lookLength
		end

		if look.held then
			look.heldAt, look.heldLength = readPart(data, offset, length, Constants.MAX_HELD)
			offset = look.heldAt + look.heldLength
		end
	end

	within(offset, footstepCount * Constants.FOOTSTEP_BYTES, length)

	for index: number = 1, footstepCount do
		into.footsteps[index] = offset
		offset += Constants.FOOTSTEP_BYTES
	end

	-- Records fill the rest, whole
	local rest: number = length - offset
	if rest % Constants.RECORD_BYTES ~= 0 then
		error(`A relay block's records end {rest % Constants.RECORD_BYTES} B into a record`)
	end

	for index: number = 1, rest // Constants.RECORD_BYTES do
		into.records[index] = offset
		offset += Constants.RECORD_BYTES
	end

	into.revealCount = revealCount
	into.hideCount = hideCount
	into.lookCount = lookCount
	into.footstepCount = footstepCount
	into.footstepData = data
	into.recordCount = rest // Constants.RECORD_BYTES
	into.recordData = data
end

--[[
    Encodes a footstep entry into the 10 B of data from offset: X and Z
    at the record's precision with the kind in X's top 4 bits, Y, and the
    ground material
--]]

function Block.writeFootstep(step: Footstep, data: buffer, offset: number)
	local kind: number? = table.find(STEPS, step.kind)
	if not kind then
		error(`A footstep's kind is Walk, Sprint, Jump or Land, not {step.kind}`)
	end

	Record.writePosition(step.at, kind - 1, 0, data, offset)
	buffer.writeu16(data, offset + 8, step.material.Value)
end

--[[
    Decodes the footstep entry at offset of data into into, erroring on a
    kind or material no value is given
--]]

function Block.readFootstep(data: buffer, offset: number, into: Footstep)
	local at: vector, xTop: number, zTop: number = Record.readPosition(data, offset)
	local kind: Step? = STEPS[xTop + 1]
	local material: Enum.Material? = Materials[buffer.readu16(data, offset + 8)]

	if not (kind and material and zTop == 0) then
		error(`The footstep entry at byte {offset} names a kind or material no value is given`)
	end

	into.at = at
	into.kind = kind
	into.material = material
end

return Block
