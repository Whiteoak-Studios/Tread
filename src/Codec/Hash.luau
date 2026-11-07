--[[
    Tread's one 32-bit FNV-1a, over a string or a range of a buffer, which
    the shared table's hash, the declarations' hash and a ladder's id run on
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)

local OFFSET: number = Constants.FNV_OFFSET
local SHIFT: number = 24 -- The prime is 2 ^ SHIFT plus a small rest, so its multiply splits into a shift and a product
local REST: number = Constants.FNV_PRIME - 2 ^ SHIFT
local WORD: number = 2 ^ 32 -- The values the hash holds

local Hash = {}

-- Folds one byte into a hash, the prime's multiply split so no product passes the 2 ^ 53 a number holds exactly
local function mix(hash: number, byte: number): number
	hash = bit32.bxor(hash, byte)

	return (bit32.lshift(hash, SHIFT) + hash * REST) % WORD
end

--[[
    The hash of a string's bytes, in order
--]]

function Hash.text(text: string): number
	local hash: number = OFFSET

	for position: number = 1, #text do
		hash = mix(hash, string.byte(text, position))
	end

	return hash
end

--[[
    The hash of length bytes of data from offset, in order, erroring on a
    range that passes either end of the buffer
--]]

function Hash.range(data: buffer, offset: number, length: number): number
	if not (offset >= 0 and length >= 0 and offset + length <= buffer.len(data)) then
		error(`A hash over {length} B from byte {offset} passes the ends of its {buffer.len(data)} B buffer`)
	end

	local hash: number = OFFSET

	for position: number = offset, offset + length - 1 do
		hash = mix(hash, buffer.readu8(data, position))
	end

	return hash
end

return Hash
