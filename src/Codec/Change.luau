--[[
    A change record, which a relay block carries in place of a whole record:
    the fields that differ from a baseline record the viewer acknowledged, and
    the store of recent records a client rebuilds each change against
--]]

--!strict
--!native
local Bits = require(script.Parent.Bits)
local Constants = require(script.Parent.Parent.Constants)

local HEADER_BYTES: number = Constants.CHANGE_HEADER_BYTES
local RECORD_BYTES: number = Constants.RECORD_BYTES
local SLOTS: number = Constants.SLOTS

-- Whiteoak TODO: A 30 Hz relay wants CHANGE_DEPTH 64, since 32 ticks of baselines last only about 1 s at 30 Hz
local DEPTH: number = Constants.CHANGE_DEPTH

-- A change's base and mask, after its slot and generation
local BASE_AT: number = 2
local MASK_AT: number = 3

-- Where each field sits in a 16 B record, as Record writes it
local X_AT: number = 2
local Z_AT: number = 5
local Y_AT: number = 8
local YAW_AT: number = 10
local PITCH_AT: number = 12
local WORD_AT: number = 13
local LAST_AT: number = 15

-- Each mask bit, low bit first, in the order its field follows the header, with Y's whole u16 in Y's place
local X_FLAG: number = 1 -- An i16 wrapped difference of the whole u24, so the platform and selector bits ride along
local Z_FLAG: number = 2
local Y_STEP_FLAG: number = 4 -- An i8 difference of the u16
local YAW_FLAG: number = 8
local PITCH_FLAG: number = 16
local WORD_FLAG: number = 32
local LAST_FLAG: number = 64
local Y_FLAG: number = 128 -- The whole u16, never beside Y_STEP_FLAG
local WIDTHS: { number } = { 2, 2, 1, 2, 1, 2, 1, 2 } -- The bytes each bit's field fills, bit 0 first
local MASKS: number = 2 ^ 8 -- The masks a u8 holds

local WRAP: number = 2 ^ 24 -- What a record's u24 X and Z wrap at
local HALF: number = WRAP / 2
local I16_LOW: number = -2 ^ 15
local I16_HIGH: number = 2 ^ 15 - 1
local I8_LOW: number = -2 ^ 7
local I8_HIGH: number = 2 ^ 7 - 1

-- A slot's entries in a store, one a tick at tick % DEPTH: the tick as an f64, then its record
local TICK_BYTES: number = 8
local ENTRY_BYTES: number = TICK_BYTES + RECORD_BYTES
local EMPTY: number = -1 -- The tick an entry no record has filled holds, which no relay tick is

-- A client's records of the last DEPTH relay ticks, a buffer of entries by slot, made at the slot's first keep
export type Store = { [number]: buffer }

-- Each mask's change record length by mask plus 1, 0 for one holding Y both ways
local Lengths: { number } = {}
for mask: number = 0, MASKS - 1 do
	local bytes: number = HEADER_BYTES
	for bit: number, width: number in WIDTHS do
		if bit32.btest(mask, 2 ^ (bit - 1)) then
			bytes += width
		end
	end

	if bit32.btest(mask, Y_STEP_FLAG) and bit32.btest(mask, Y_FLAG) then
		bytes = 0
	end

	Lengths[mask + 1] = bytes
end

local Change = {
	-- Each mask bit, for a reader that walks a change's fields without a baseline
	X = X_FLAG,
	Z = Z_FLAG,
	Y_STEP = Y_STEP_FLAG,
	YAW = YAW_FLAG,
	PITCH = PITCH_FLAG,
	WORD = WORD_FLAG,
	LAST = LAST_FLAG,
	Y = Y_FLAG,
}

-- The signed difference a - b of two u24s, the shorter way round their wrap
local function wrapped(a: number, b: number): number
	return (a - b + HALF) % WRAP - HALF
end

--[[
    The bytes a change record fills for its mask, header included, and 0
    for a mask no change carries, one holding Y both as a step and whole
--]]

function Change.length(mask: number): number
	return Lengths[mask + 1] or 0
end

--[[
    Writes the change of current's 16 B record against baseline's at at of
    into, each field present exactly when its bytes differ, and gives its
    bytes. It writes nothing and gives 0 when the record must go whole: the
    two are other lives, base is outside 1 to 31, or X or Z moved past what
    an i16 difference holds
--]]

function Change.write(
	current: buffer,
	currentAt: number,
	baseline: buffer,
	baselineAt: number,
	base: number,
	into: buffer,
	at: number
): number
	local id: number = buffer.readu16(current, currentAt)
	local dx: number = wrapped(Bits.readu24(current, currentAt + X_AT), Bits.readu24(baseline, baselineAt + X_AT))
	local dz: number = wrapped(Bits.readu24(current, currentAt + Z_AT), Bits.readu24(baseline, baselineAt + Z_AT))

	if
		id ~= buffer.readu16(baseline, baselineAt)
		or base < 1
		or base >= DEPTH
		or dx < I16_LOW
		or dx > I16_HIGH
		or dz < I16_LOW
		or dz > I16_HIGH
	then
		return 0
	end

	local offset: number = at + HEADER_BYTES
	local mask: number = 0

	if dx ~= 0 then
		buffer.writei16(into, offset, dx)
		offset += 2
		mask += X_FLAG
	end

	if dz ~= 0 then
		buffer.writei16(into, offset, dz)
		offset += 2
		mask += Z_FLAG
	end

	-- Y as a step while one holds it, whole past that
	local y: number = buffer.readu16(current, currentAt + Y_AT)
	local dy: number = y - buffer.readu16(baseline, baselineAt + Y_AT)
	if dy ~= 0 and dy >= I8_LOW and dy <= I8_HIGH then
		buffer.writei8(into, offset, dy)
		offset += 1
		mask += Y_STEP_FLAG
	elseif dy ~= 0 then
		buffer.writeu16(into, offset, y)
		offset += 2
		mask += Y_FLAG
	end

	-- The rest go as the record has them
	local yaw: number = buffer.readu16(current, currentAt + YAW_AT)
	if yaw ~= buffer.readu16(baseline, baselineAt + YAW_AT) then
		buffer.writeu16(into, offset, yaw)
		offset += 2
		mask += YAW_FLAG
	end

	local pitch: number = buffer.readu8(current, currentAt + PITCH_AT)
	if pitch ~= buffer.readu8(baseline, baselineAt + PITCH_AT) then
		buffer.writeu8(into, offset, pitch)
		offset += 1
		mask += PITCH_FLAG
	end

	local word: number = buffer.readu16(current, currentAt + WORD_AT)
	if word ~= buffer.readu16(baseline, baselineAt + WORD_AT) then
		buffer.writeu16(into, offset, word)
		offset += 2
		mask += WORD_FLAG
	end

	local last: number = buffer.readu8(current, currentAt + LAST_AT)
	if last ~= buffer.readu8(baseline, baselineAt + LAST_AT) then
		buffer.writeu8(into, offset, last)
		offset += 1
		mask += LAST_FLAG
	end

	buffer.writeu16(into, at, id)
	buffer.writeu8(into, at + BASE_AT, base)
	buffer.writeu8(into, at + MASK_AT, mask)

	return offset - at
end

--[[
    Rebuilds the 16 B record the change at at of data names into into at
    intoAt, baseline's record with the change's fields over it, and gives
    the change's bytes. It errors on a base outside 1 to 31, a mask holding
    Y both ways, a change past data's end, and a baseline of another life
--]]

function Change.read(
	data: buffer,
	at: number,
	baseline: buffer,
	baselineAt: number,
	into: buffer,
	intoAt: number
): number
	local length: number = buffer.len(data)
	if at + HEADER_BYTES > length then
		error(`Change.read: the change at byte {at} runs past its data's {length} B`)
	end

	local id: number = buffer.readu16(data, at)
	local base: number = buffer.readu8(data, at + BASE_AT)
	local mask: number = buffer.readu8(data, at + MASK_AT)
	local bytes: number = Change.length(mask)

	if base < 1 or base >= DEPTH then
		error(`Change.read: a change's base is 1 to {DEPTH - 1} relay ticks back, not {base}`)
	elseif bytes == 0 then
		error(`Change.read: a change's mask {mask} holds Y both as a step and whole`)
	elseif at + bytes > length then
		error(`Change.read: the change at byte {at} runs past its data's {length} B`)
	elseif id ~= buffer.readu16(baseline, baselineAt) then
		error(`Change.read: a change of character {id} names a baseline of {buffer.readu16(baseline, baselineAt)}`)
	end

	buffer.copy(into, intoAt, baseline, baselineAt, RECORD_BYTES)
	local offset: number = at + HEADER_BYTES

	if bit32.btest(mask, X_FLAG) then
		Bits.writeu24(into, intoAt + X_AT, (Bits.readu24(into, intoAt + X_AT) + buffer.readi16(data, offset)) % WRAP)
		offset += 2
	end

	if bit32.btest(mask, Z_FLAG) then
		Bits.writeu24(into, intoAt + Z_AT, (Bits.readu24(into, intoAt + Z_AT) + buffer.readi16(data, offset)) % WRAP)
		offset += 2
	end

	if bit32.btest(mask, Y_STEP_FLAG) then
		buffer.writeu16(into, intoAt + Y_AT, buffer.readu16(into, intoAt + Y_AT) + buffer.readi8(data, offset))
		offset += 1
	elseif bit32.btest(mask, Y_FLAG) then
		buffer.copy(into, intoAt + Y_AT, data, offset, 2)
		offset += 2
	end

	if bit32.btest(mask, YAW_FLAG) then
		buffer.copy(into, intoAt + YAW_AT, data, offset, 2)
		offset += 2
	end

	if bit32.btest(mask, PITCH_FLAG) then
		buffer.copy(into, intoAt + PITCH_AT, data, offset, 1)
		offset += 1
	end

	if bit32.btest(mask, WORD_FLAG) then
		buffer.copy(into, intoAt + WORD_AT, data, offset, 2)
		offset += 2
	end

	if bit32.btest(mask, LAST_FLAG) then
		buffer.copy(into, intoAt + LAST_AT, data, offset, 1)
	end

	return bytes
end

--[[
    An empty store, which a client keeps the records of its last 32 relay
    ticks in, about 768 B a slot it has kept a record of
--]]

function Change.store(): Store
	return {}
end

--[[
    Files the 16 B record at at of data as its slot's record at an
    unwrapped relay tick, over the one 32 ticks older, making the slot's
    entries at its first record and reusing them after
--]]

function Change.keep(store: Store, tick: number, data: buffer, at: number)
	local slot: number = buffer.readu16(data, at) % SLOTS
	if not store[slot] then
		local made: buffer = buffer.create(DEPTH * ENTRY_BYTES)
		for entry: number = 0, DEPTH - 1 do
			buffer.writef64(made, entry * ENTRY_BYTES, EMPTY)
		end

		store[slot] = made
	end

	local entries: buffer = store[slot]
	local offset: number = tick % DEPTH * ENTRY_BYTES
	buffer.writef64(entries, offset, tick)
	buffer.copy(entries, offset + TICK_BYTES, data, at, RECORD_BYTES)
end

--[[
    The buffer and offset of the record a store holds for a character, its
    slot and generation as the u16 id, at an unwrapped relay tick, or nil
    when the store holds another tick's or another life's there
--]]

function Change.find(store: Store, id: number, tick: number): (buffer?, number)
	local entries: buffer? = store[id % SLOTS]
	local offset: number = tick % DEPTH * ENTRY_BYTES

	if not entries or buffer.readf64(entries, offset) ~= tick or buffer.readu16(entries, offset + TICK_BYTES) ~= id then
		return nil, 0
	end

	return entries, offset + TICK_BYTES
end

return Change
