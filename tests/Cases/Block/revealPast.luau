--[[
    A player's reveal carries 0, 1, 3 or 7 past records behind its entry
    beside every other section, a block with no past keeps its old bytes,
    and the past counts toward the block's 896 B
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SEQUENCE: number = 513
local TICK: number = 2000
local GENERATION: number = 6
local BASE: number = 3 -- The change record's base, relay ticks back
local LOOK: number = 64 -- The largest look and held item, in bytes
local HELD: number = 16
local FULL: { number } = { 31, 20, 9, 6, 3, 2, 1 } -- A whole past, oldest first, its first the oldest a client keeps

type Past = { slot: number, ages: { number } }

-- Each player reveal's slot and its past records' ages, oldest first: none, one, three and a whole past
local PASTS: { Past } = {
	{ slot = 700, ages = {} },
	{ slot = 701, ages = { 2 } },
	{ slot = 702, ages = { 9, 4, 1 } },
	{ slot = 703, ages = FULL },
}

-- The kind byte each reveal goes out with, a Sleeper's last: the past's count in the top 3 bits, the kind code below
local KIND_BYTES: { number } = { 0x00, 0x20, 0x60, 0xE0, 0x03 }

-- A block with no past as the layout lays it: the header, a reveal of each kind, then a culled hide
local BARE: { number } = {
	7,
	0,
	0xE8,
	0x03,
	4,
	1,
	0,
	0,
	0,
	0x01,
	0x20,
	0,
	0x02,
	0x30,
	1,
	0x03,
	0x40,
	2,
	0x04,
	0x50,
	3,
	0x05,
	0x60,
	1,
}

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Change: any = globals.require(tread.Codec.Change)
	local Constants: any = globals.require(tread.Constants)
	local Record: any = globals.require(tread.Codec.Record)
	local roblox: any = require("@lune/roblox")
	local entry: number = Constants.PAST_BYTES

	-- A record of slot at a place of its own, encoded at offset of data
	local function encode(slot: number, place: number, data: buffer, offset: number)
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = slot, GENERATION
		record.position = vector.create(place, place / 4, -place)
		record.yaw = place / 100
		Record.write(record, data, offset, Game.limits)
	end

	-- A past of slot written into pool from at, oldest first, each record at a place its age gives, and where it ends
	local function lay(slot: number, ages: { number }, pool: buffer, at: number): number
		for _, age: number in ages do
			buffer.writeu8(pool, at, age)
			encode(slot, slot + age, pool, at + 1)
			at += entry
		end

		return at
	end

	-- Every past in one pool, the last reveal's first, behind a byte no past starts at
	local pool: buffer = buffer.create(1 + 11 * entry)
	local reveals: { { [string]: any } } = table.create(#PASTS)
	local filled: number = 1
	for index: number = #PASTS, 1, -1 do
		local past: Past = PASTS[index]
		reveals[index] =
			{ slot = past.slot, generation = GENERATION, kind = "Player", pastCount = #past.ages, pastAt = filled }
		filled = lay(past.slot, past.ages, pool, filled)
	end

	table.insert(reveals, { slot = 704, generation = GENERATION, kind = "Sleeper" })

	-- Two hides, a look entry holding its look alone, a footstep entry, two whole records and a change record
	local parts: buffer = buffer.create(2)
	buffer.writeu8(parts, 0, 7)
	buffer.writeu8(parts, 1, 9)

	local steps: buffer = buffer.create(10)
	local step: { [string]: any } =
		{ at = vector.create(1, 2, 3), kind = "Walk", material = roblox.Enum.Material.Grass }
	Block.writeFootstep(step, steps, 0)

	local wholes: buffer = buffer.create(32)
	encode(700, 1, wholes, 0)
	encode(703, 2, wholes, 16)

	local baseline: buffer = buffer.create(16)
	local current: buffer = buffer.create(16)
	local changes: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	encode(702, 5, baseline, 0)
	encode(702, 6, current, 0)
	local changeLength: number = Change.write(current, 0, baseline, 0, BASE, changes, 0)

	local block: any = Block.new()
	block.sequence, block.tick = SEQUENCE, TICK
	block.reveals, block.revealCount, block.pastData = reveals, #reveals, pool
	block.hides, block.hideCount =
		{ { slot = 705, generation = 1, culled = true }, { slot = 706, generation = 2, culled = false } }, 2
	block.looks[1] = {
		slot = 700,
		generation = GENERATION,
		look = true,
		lookData = parts,
		lookAt = 0,
		lookLength = 2,
		held = false,
		heldData = parts,
		heldAt = 0,
		heldLength = 0,
	}
	block.lookCount = 1
	block.footstepData, block.footsteps, block.footstepCount = steps, { 0 }, 1
	block.recordData, block.records, block.recordCount = wholes, { 0, 16 }, 2
	block.changeData, block.changeOffsets, block.changeLengths, block.changeCount = changes, { 0 }, { changeLength }, 1

	local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local bytes: number = Block.write(block, data)
	local size: number = 9 + 5 * 3 + 11 * entry + 2 * 3 + (4 + 2) + 10 + 2 * 16 + changeLength
	if changeLength == 0 then
		return false, "The change record went whole, so the block carries none"
	elseif bytes ~= size then
		return false, `The block filled {bytes} B, where its sections and 11 past records fill {size}`
	end

	-- Each reveal's entry, then its past as the pool holds it, straight behind it
	local starts: { number } = {}
	local offset: number = 9
	for index: number, reveal: { [string]: any } in reveals do
		local length: number = (reveal.pastCount or 0) * entry
		if buffer.readu16(data, offset) ~= Record.id(reveal.slot, GENERATION) then
			return false, `Reveal {index} isn't at byte {offset}`
		elseif buffer.readu8(data, offset + 2) ~= KIND_BYTES[index] then
			return false, `Reveal {index}'s kind byte is {buffer.readu8(data, offset + 2)}, not {KIND_BYTES[index]}`
		elseif
			length > 0
			and buffer.readstring(data, offset + 3, length) ~= buffer.readstring(pool, reveal.pastAt, length)
		then
			return false, `Reveal {index}'s past isn't the {length} B straight behind its entry`
		end

		starts[index] = offset + 3
		offset += 3 + length
	end

	if buffer.readu16(data, offset) ~= Record.id(705, 1) then
		return false, `The hides don't start at byte {offset}, straight after the last reveal`
	end

	-- Read back, each past where it lies in the block's own bytes and none on the reveals without one
	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, data, 0, bytes)

	local read: any = Block.new()
	Block.read(exact, read)
	if read.revealCount ~= 5 or read.pastData ~= exact then
		return false, `The block read back {read.revealCount} reveals, their pasts in another buffer`
	end

	for index: number, reveal: { [string]: any } in reveals do
		local back: { [string]: any } = read.reveals[index]
		local count: number = reveal.pastCount or 0
		if back.slot ~= reveal.slot or back.generation ~= GENERATION or back.kind ~= reveal.kind then
			return false, `Reveal {index} read back as slot {back.slot} of {back.kind}`
		elseif count == 0 and (back.pastCount ~= nil or back.pastAt ~= nil) then
			return false, `Reveal {index} read back a past of {back.pastCount}, where it carries none`
		elseif count > 0 and (back.pastCount ~= count or back.pastAt ~= starts[index]) then
			local found: string = `{back.pastCount} past records at {back.pastAt}`
			return false, `Reveal {index} read back {found}, not {count} at {starts[index]}`
		end
	end

	-- The sections behind the pasts, each where it lies
	for index: number = 1, 2 do
		local differs: string? = Same(block.hides[index], read.hides[index], `hide {index}`)
		if differs then
			return false, differs
		end
	end

	local look: { [string]: any } = read.looks[1]
	if
		read.lookCount ~= 1
		or look.slot ~= 700
		or look.lookLength ~= 2
		or buffer.readu8(exact, look.lookAt + 1) ~= 9
	then
		return false, "The look entry read back other than it was written"
	end

	local stepBack: { [string]: any } = { at = vector.zero, kind = "Land", material = roblox.Enum.Material.Air }
	Block.readFootstep(exact, read.footsteps[1], stepBack)
	local differs: string? = Same(step, stepBack, "footstep")
	if differs then
		return false, differs
	elseif read.recordCount ~= 2 or buffer.readu16(exact, read.records[2]) ~= Record.id(703, GENERATION) then
		return false, "The whole records read back out of place"
	elseif
		read.changeCount ~= 1
		or read.changeLengths[1] ~= changeLength
		or buffer.readstring(exact, read.changeOffsets[1], changeLength)
			~= buffer.readstring(changes, 0, changeLength)
	then
		return false, "The change record read back out of place"
	end

	-- The block as read writes back the same bytes, each past copied from where it lies
	local again: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	if Block.write(read, again) ~= bytes or buffer.readstring(again, 0, bytes) ~= buffer.tostring(exact) then
		return false, "The block as read wrote back other bytes"
	end

	-- A block with no past, a reveal handed a count of 0 and the block no pool, lays its bytes as before
	local bare: any = Block.new()
	bare.sequence, bare.tick, bare.pastData = 7, 1000, nil
	bare.reveals = {
		{ slot = 1, generation = 2, kind = "Player" },
		{ slot = 2, generation = 3, kind = "Npc", pastCount = 0 },
		{ slot = 3, generation = 4, kind = "Body" },
		{ slot = 4, generation = 5, kind = "Sleeper", pastCount = 0, pastAt = 5 },
	}
	bare.revealCount = 4
	bare.hides, bare.hideCount = { { slot = 5, generation = 6, culled = true } }, 1

	local bareBytes: number = Block.write(bare, data)
	if bareBytes ~= #BARE then
		return false, `The block with no past filled {bareBytes} B, not the {#BARE} it filled before`
	end

	for index: number, byte: number in BARE do
		if buffer.readu8(data, index - 1) ~= byte then
			return false, `Byte {index - 1} of the block with no past is {buffer.readu8(data, index - 1)}, not {byte}`
		end
	end

	-- Read into the table that held the pasts, no reveal keeps one
	local plain: buffer = buffer.create(bareBytes)
	buffer.copy(plain, 0, data, 0, bareBytes)
	Block.read(plain, read)
	for index: number = 1, 4 do
		if read.reveals[index].pastCount ~= nil or read.reveals[index].pastAt ~= nil then
			return false, `Reveal {index} kept a past from the block read before it`
		end
	end

	-- Whole pasts beside the largest looks and records: 3 reveals fill 9 + 3 * 223 B, and a fourth passes 896 B
	local full: buffer = buffer.create(4 * #FULL * entry)
	for index: number = 1, 4 do
		lay(index, FULL, full, (index - 1) * #FULL * entry)
	end

	local largestParts: buffer = buffer.create(LOOK + HELD)
	local records: buffer = buffer.create(4 * 16)
	local function largest(count: number): any
		local made: any = Block.new()
		made.recordData, made.pastData = records, full

		for index: number = 1, count do
			made.reveals[index] = {
				slot = index,
				generation = GENERATION,
				kind = "Player",
				pastCount = #FULL,
				pastAt = (index - 1) * #FULL * entry,
			}
			made.looks[index] = {
				slot = index,
				generation = GENERATION,
				look = true,
				lookData = largestParts,
				lookAt = 0,
				lookLength = LOOK,
				held = true,
				heldData = largestParts,
				heldAt = LOOK,
				heldLength = HELD,
			}
			made.records[index] = (index - 1) * 16
		end

		made.revealCount, made.lookCount, made.recordCount = count, count, count

		return made
	end

	local room: buffer = buffer.create(1024)
	if Block.write(largest(3), room) ~= 9 + 3 * 223 then
		return false, "3 reveals with whole pasts, their largest looks and records didn't fill 9 + 3 * 223 B"
	end

	local refused: boolean, why: string = Refuses("passes its 896 B", Block.write, largest(4), room)
	if not refused then
		return false, `A fourth reveal with a whole past was written: {why}`
	end

	return true, nil
end
