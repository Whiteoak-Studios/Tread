--[[
    The probe's stream hash, FNV over 32-bit words, at answers worked out
    apart from the module: the offset basis for nothing, one word, the f64
    1, and a refusal of bytes that end inside a word
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local OFFSET_BASIS: number = 2166136261 -- FNV's start, the hash of no words
local ZERO_WORD: number = 84696351 -- The basis times the FNV prime, 16777619, mod 2^32
local ONE_WORD: number = 67918732 -- The basis with its low bit flipped, times the prime
local F64_ONE: number = 4198930381 -- The words 0 and 0x3FF00000, the f64 1 low word first
local WORD_BYTES: number = 4
local CUT_BYTES: number = 6

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local one: buffer = buffer.create(WORD_BYTES)
	buffer.writeu32(one, 0, 1)

	local double: buffer = buffer.create(2 * WORD_BYTES)
	buffer.writef64(double, 0, 1)

	local answers: { { stream: buffer, expected: number, name: string } } = {
		{ stream = buffer.create(0), expected = OFFSET_BASIS, name = "no words" },
		{ stream = buffer.create(WORD_BYTES), expected = ZERO_WORD, name = "a zero word" },
		{ stream = one, expected = ONE_WORD, name = "the word 1" },
		{ stream = double, expected = F64_ONE, name = "the f64 1" },
	}

	for _, answer in answers do
		local hashed: number = Queries.hash(answer.stream)
		if hashed ~= answer.expected then
			return false, `{answer.name} hashed to {hashed}, not {answer.expected}`
		end
	end

	local took: boolean = pcall(Queries.hash, buffer.create(CUT_BYTES))
	if took then
		return false, `{CUT_BYTES} B, which end inside a word, were hashed`
	end

	return true, nil
end
