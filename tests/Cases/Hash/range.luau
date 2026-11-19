--[[
    Hash.range gives FNV-1a over just the bytes of its range, every byte
    value from 0 to 255 included, and refuses a range past either end of
    its buffer
--]]

--!strict
local Environment = require("../../Environment")

local HASH: string = "src/Codec/Hash.luau"
local PADDED: string = "xfoobarx" -- "foobar" with a byte either side that the ranges leave out
local BYTE_VALUES: number = 256
local EVERY_BYTE: number = 0x90A458C5 -- FNV-1a over the bytes 0 to 255 in order, from a reference outside Tread

type Span = { offset: number, length: number }
type Range = { offset: number, length: number, expected: number }

return function (): (boolean, string | nil)
	local Hash = Environment.load(HASH)
	local data: buffer = buffer.fromstring(PADDED)

	local ranges: { Range } = {
		{ offset = 1, length = 6, expected = 0xBF9CF968 }, -- "foobar"
		{ offset = 1, length = 3, expected = 0xA9F37ED7 }, -- "foo"
		{ offset = 0, length = 0, expected = 0x811C9DC5 }, -- Nothing, the offset basis
		{ offset = #PADDED, length = 0, expected = 0x811C9DC5 }, -- Nothing, at the buffer's end
	}

	for _, range: Range in ranges do
		local hash: number = Hash.range(data, range.offset, range.length)
		if hash ~= range.expected then
			return false, `{range.length} B from byte {range.offset} hashed to {hash}, not {range.expected}`
		end
	end

	-- Every byte value, the ones above 127 among them
	local every: buffer = buffer.create(BYTE_VALUES)
	for value: number = 0, BYTE_VALUES - 1 do
		buffer.writeu8(every, value, value)
	end

	if Hash.range(every, 0, BYTE_VALUES) ~= EVERY_BYTE then
		return false, `The bytes 0 to 255 hashed to {Hash.range(every, 0, BYTE_VALUES)}, not {EVERY_BYTE}`
	end

	local refused: { Span } = {
		{ offset = -1, length = 2 },
		{ offset = 0, length = -1 },
		{ offset = 3, length = #PADDED - 2 },
		{ offset = #PADDED + 1, length = 0 },
	}

	for _, range: Span in refused do
		if pcall(Hash.range, data, range.offset, range.length) then
			return false, `{range.length} B from byte {range.offset} of a {#PADDED} B buffer was hashed`
		end
	end

	return true, nil
end
