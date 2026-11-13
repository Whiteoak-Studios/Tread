--[[
    The shared table's hash is a 32-bit FNV-1a over the bytes its doc gives,
    checked against a reference that matches FNV-1a's published vectors, and
    the fixture's hash is a whole number a u32 holds
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

local OFFSET: number = 0x811C9DC5 -- 32-bit FNV-1a's offset basis
local PRIME: number = 0x01000193
local HALF: number = 2 ^ 16 -- The reference multiplies a hash in two 16-bit halves
local WORD: number = 2 ^ 32

-- Config.hash's tags, written in front of each value
local BOOLEAN: number = 1
local NUMBER: number = 2
local STRING: number = 3
local VECTOR: number = 4
local TABLE: number = 6
local END: number = 7

local EMPTY_FORMAT: string = "<BB" -- An empty table's two tags
local VALUES_FORMAT: string = "<BBs4BBBs4BdBs4BdddB" -- Three keys, each a string, with a boolean, number and Vector3

-- FNV-1a's published vectors for "", "a" and "foobar"
local VECTORS: { [string]: number } = {
	[""] = 0x811C9DC5,
	a = 0xE40C292C,
	foobar = 0xBF9CF968,
}

-- A reference 32-bit FNV-1a, with a multiply of its own beside Config's
local function fnv(bytes: string): number
	local hash: number = OFFSET

	for index: number = 1, #bytes do
		local byte: number = string.byte(bytes, index)
		hash = bit32.bxor(hash, byte)

		local high: number = hash // HALF
		local low: number = hash % HALF
		hash = ((high * PRIME) % HALF * HALF + low * PRIME) % WORD
	end

	return hash
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for text: string, expected: number in VECTORS do
		if fnv(text) ~= expected then
			return false, `The reference gives {fnv(text)} for "{text}", where FNV-1a gives {expected}`
		end
	end

	-- An empty table is its tag and the end tag
	local empty: string = string.pack(EMPTY_FORMAT, TABLE, END)
	if Config.hash({}) ~= fnv(empty) then
		return false, `An empty table hashed to {Config.hash({})}, not {fnv(empty)}`
	end

	-- Each key in sorted order, a string, then its value: a boolean, a number's 8 bytes, a Vector3's three
	local values: { [string]: any } = { v = roblox.Vector3.new(1, 2, 3), n = 1.5, a = true }
	local written: string = string.pack(
		VALUES_FORMAT,
		TABLE,
		STRING,
		"a",
		BOOLEAN,
		1,
		STRING,
		"n",
		NUMBER,
		1.5,
		STRING,
		"v",
		VECTOR,
		1,
		2,
		3,
		END
	)

	if Config.hash(values) ~= fnv(written) then
		return false, `A table of three values hashed to {Config.hash(values)}, not {fnv(written)}`
	end

	local hash: number = Config.hash(Example.shared())
	if hash % 1 ~= 0 or hash < 0 or hash >= WORD then
		return false, `The fixture's hash, {hash}, is no u32`
	end

	return true, nil
end
