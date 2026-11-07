--[[
    Hash.text gives FNV-1a's published 32-bit values, from the empty string's
    offset basis to "foobar"
--]]

--!strict
local Environment = require("../../Environment")

local HASH: string = "src/Codec/Hash.luau"

-- FNV-1a's published 32-bit test vectors
local VECTORS: { [string]: number } = {
	[""] = 0x811C9DC5,
	a = 0xE40C292C,
	b = 0xE70C2DE5,
	c = 0xE60C2C52,
	foo = 0xA9F37ED7,
	foobar = 0xBF9CF968,
}

return function (): (boolean, string | nil)
	local Hash = Environment.load(HASH)

	for text: string, expected: number in VECTORS do
		local hash: number = Hash.text(text)
		if hash ~= expected then
			return false, `"{text}" hashed to {hash}, where FNV-1a gives {expected}`
		end
	end

	return true, nil
end
