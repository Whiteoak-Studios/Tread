--[[
    What a value that crossed between VMs is described as: a buffer and a
    string by their bytes, a table by its entries sorted with its frozen and
    metatable flags, nested tables inside it, and nil and the rest by type
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local WORK: string = "dev/Server/Parallel/Work.luau"
local BUFFER_BYTES: number = 16
local STRING_BYTES: number = 5
local SMALL_BYTES: number = 3

return function (): (boolean, string | nil)
	local Work: any = Harness.new().load(WORK)

	-- Each value beside what it must be described as
	local cases: { { value: any, expected: string } } = {
		{ value = buffer.create(BUFFER_BYTES), expected = "buffer of 16 B" },
		{ value = string.rep("x", STRING_BYTES), expected = "string of 5 B" },
		{ value = nil, expected = "nil" },
		{ value = 42, expected = "number 42" },
		{ value = true, expected = "boolean true" },
		{
			value = { list = { 1, 2 }, inner = { flag = true } },
			expected = "table (inner: table (flag: boolean true), list: table (1: number 1, 2: number 2))",
		},
		{
			value = table.freeze(setmetatable({ answer = 42 }, { __index = {} })),
			expected = "table (answer: number 42), frozen, with a metatable",
		},
		{
			value = { buffer.create(SMALL_BYTES), buffer.create(SMALL_BYTES) },
			expected = "table (1: buffer of 3 B, 2: buffer of 3 B)",
		},
		{ value = {}, expected = "table ()" },
	}

	for index: number, case in cases do
		local described: string = Work.describe(case.value)
		if described ~= case.expected then
			return false, `Value {index} was described as "{described}", not "{case.expected}"`
		end
	end

	return true, nil
end
