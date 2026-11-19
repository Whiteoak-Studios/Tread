--[[
    Bits packs low bit first across byte boundaries, pads to a whole byte
    with zeros over a buffer's stale bytes, reads every width from 0 to 32
    back, and reuses the cursor it is handed
--]]

--!strict
local Environment = require("../../Environment")

local BITS: string = "src/Codec/Bits.luau"
local STALE: number = 255 -- What the buffer held before, which every byte a write starts must lose
local WIDEST: number = 32

return function (): (boolean, string | nil)
	local Bits: any = Environment.load(BITS)

	-- 1 in 1 bit, 5 in 3, 171 in 8 and 3 in 2, from byte 1: 1 + 5 * 2 + 11 * 16, then 10 + 3 * 16
	local data: buffer = buffer.create(4)
	buffer.fill(data, 0, STALE)

	local writer: any = Bits.writer(data, 1, 3)
	Bits.write(writer, 1, 1)
	Bits.write(writer, 5, 3)
	Bits.write(writer, 171, 8)
	Bits.write(writer, 3, 2)

	local bytes: { number } = { buffer.readu8(data, 0), buffer.readu8(data, 1), buffer.readu8(data, 2) }
	if bytes[1] ~= STALE or bytes[2] ~= 187 or bytes[3] ~= 58 or buffer.readu8(data, 3) ~= STALE then
		return false, `The packing wrote {table.concat(bytes, ", ")}, where 255, 187, 58 were expected`
	elseif Bits.bytes(writer) ~= 2 then
		return false, `14 bits fill {Bits.bytes(writer)} bytes by Bits.bytes, where they fill 2`
	end

	local reader: any = Bits.reader(data, 1, 2)
	local read: { number? } = { Bits.read(reader, 1), Bits.read(reader, 3), Bits.read(reader, 8), Bits.read(reader, 2) }
	if read[1] ~= 1 or read[2] ~= 5 or read[3] ~= 171 or read[4] ~= 3 then
		return false, "The packing read back other values than it was written with"
	elseif Bits.read(reader, 2) ~= 0 or Bits.read(reader, 1) ~= nil then
		return false, "The padding read other than 0, or a read past the stretch gave something other than nil"
	end

	-- Every width at its top, at 0 and at a middle value, one after another across the byte boundaries
	local wide: buffer = buffer.create(3 * (WIDEST + 1) * 4)
	local cursor: any = Bits.writer(wide, 0, buffer.len(wide))
	for width: number = 0, WIDEST do
		Bits.write(cursor, 2 ^ width - 1, width)
		Bits.write(cursor, 0, width)
		Bits.write(cursor, 2 ^ width // 3, width)
	end

	-- Aiming the same cursor again reuses it from the stretch's start
	if Bits.reader(wide, 0, buffer.len(wide), cursor) ~= cursor or cursor.bit ~= 0 then
		return false, "Aiming a cursor again made a new one or kept its place"
	end

	for width: number = 0, WIDEST do
		local top: number? = Bits.read(cursor, width)
		local zero: number? = Bits.read(cursor, width)
		local middle: number? = Bits.read(cursor, width)

		if top ~= 2 ^ width - 1 or zero ~= 0 or middle ~= 2 ^ width // 3 then
			return false, `{width} bits read back {top}, {zero} and {middle}`
		end
	end

	-- A u24 at its edges
	local u24: buffer = buffer.create(6)
	Bits.writeu24(u24, 0, 0)
	Bits.writeu24(u24, 3, 2 ^ 24 - 1)
	if Bits.readu24(u24, 0) ~= 0 or Bits.readu24(u24, 3) ~= 2 ^ 24 - 1 then
		return false, "A u24 read back other than 0 and 2 ^ 24 - 1"
	end

	return true, nil
end
