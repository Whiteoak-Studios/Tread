--[[
    The bit packer every layout's game fields go through, a cursor over a
    stretch of a buffer the caller reuses, written and read low bit first,
    and the u24 the layouts' positions ride in
--]]

--!strict
--!native

local BYTE_BITS: number = 8
local WIDEST: number = 32 -- The widest value one write or read takes, what bit32 holds
local U16: number = 2 ^ 16 -- A u24's low two bytes hold this many values

-- A stretch of a buffer being written or read, which its owner aims again for each layout it packs
export type Cursor = {
	data: buffer,
	offset: number, -- The byte its stretch starts at
	bit: number, -- The bits written or read so far
	bits: number, -- The most bits its stretch holds
}

local Bits = {}

-- Aims cursor, or a new one when none is given, at bytes bytes of data from offset, with nothing taken yet
local function aim(data: buffer, offset: number, bytes: number, cursor: Cursor?): Cursor
	if not (offset >= 0 and bytes >= 0 and offset + bytes <= buffer.len(data)) then
		error(`A cursor over {bytes} B from byte {offset} passes the end of its {buffer.len(data)} B buffer`)
	end

	if not cursor then
		return { data = data, offset = offset, bit = 0, bits = bytes * BYTE_BITS }
	end

	cursor.data = data
	cursor.offset = offset
	cursor.bit = 0
	cursor.bits = bytes * BYTE_BITS

	return cursor
end

--[[
    A cursor that writes up to bytes bytes of data from offset. It reuses
    the cursor given, so a layout packed every tick makes no table
--]]

function Bits.writer(data: buffer, offset: number, bytes: number, cursor: Cursor?): Cursor
	return aim(data, offset, bytes, cursor)
end

--[[
    A cursor that reads up to bytes bytes of data from offset, reusing the
    cursor given
--]]

function Bits.reader(data: buffer, offset: number, bytes: number, cursor: Cursor?): Cursor
	return aim(data, offset, bytes, cursor)
end

--[[
    Writes value, a whole number from 0 below 2 ^ width, into the cursor's
    next width bits. Each byte it starts it writes whole, so every bit past
    the last write is 0 and the stretch pads to a whole byte with zeros
--]]

function Bits.write(cursor: Cursor, value: number, width: number)
	local position: number = cursor.bit

	if not (width >= 0 and width <= WIDEST and position + width <= cursor.bits) then
		error(`A write of {width} bits at bit {position} passes its cursor's {cursor.bits} bits`)
	elseif width == 0 then
		if value ~= 0 then
			error(`{value} doesn't fit in 0 bits`)
		end

		return
	elseif bit32.extract(value, 0, width) ~= value then
		error(`{value} is no whole number from 0 below 2 ^ {width}`)
	end

	local data: buffer = cursor.data
	local consumed: number = 0

	while consumed < width do
		local index: number = cursor.offset + position // BYTE_BITS
		local shift: number = position % BYTE_BITS
		local take: number = math.min(BYTE_BITS - shift, width - consumed)
		local chunk: number = bit32.extract(value, consumed, take)

		-- A byte's first write sets it whole, which leaves its bits above the chunk at 0
		if shift == 0 then
			buffer.writeu8(data, index, chunk)
		else
			buffer.writeu8(data, index, bit32.replace(buffer.readu8(data, index), chunk, shift, take))
		end

		position += take
		consumed += take
	end

	cursor.bit = position
end

--[[
    Reads the cursor's next width bits as a whole number, or nil when they
    would run past the end of its stretch
--]]

function Bits.read(cursor: Cursor, width: number): number?
	local position: number = cursor.bit

	if not (width >= 0 and width <= WIDEST) then
		error(`A read of {width} bits is wider than the {WIDEST} one read takes`)
	elseif position + width > cursor.bits then
		return nil
	end

	local data: buffer = cursor.data
	local value: number = 0
	local consumed: number = 0

	while consumed < width do
		local index: number = cursor.offset + position // BYTE_BITS
		local shift: number = position % BYTE_BITS
		local take: number = math.min(BYTE_BITS - shift, width - consumed)

		value = bit32.replace(value, bit32.extract(buffer.readu8(data, index), shift, take), consumed, take)
		position += take
		consumed += take
	end

	cursor.bit = position

	return value
end

--[[
    The whole bytes the cursor's bits so far fill, its last one padded
--]]

function Bits.bytes(cursor: Cursor): number
	return (cursor.bit + BYTE_BITS - 1) // BYTE_BITS
end

--[[
    Writes a u24, the low two bytes then the top one, little-endian as the
    buffer library writes the rest
--]]

function Bits.writeu24(data: buffer, offset: number, value: number)
	buffer.writeu16(data, offset, value % U16)
	buffer.writeu8(data, offset + 2, value // U16)
end

function Bits.readu24(data: buffer, offset: number): number
	return buffer.readu16(data, offset) + buffer.readu8(data, offset + 2) * U16
end

return Bits
