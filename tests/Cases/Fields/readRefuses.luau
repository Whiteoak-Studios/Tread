--[[
    Fields.read refuses bytes that don't hold the list, giving the index of
    the first field that failed: a value outside its declared range, a list
    past its count, bytes that run out, and one past the last field for
    bytes left over or padding that isn't 0
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local FIELDS: string = "src/Codec/Fields.luau"
local PAST: number = 12 -- One past the command list's last field, 11

type Row = { name: string, edge: string, length: number?, patch: ((data: buffer) -> ())?, index: number? }

-- Sets bits at bit position of data to value, so a packing holds what no write would make
local function set(data: buffer, position: number, width: number, value: number)
	local index: number = position // 8
	local shift: number = position % 8
	local word: number = buffer.readu16(data, index)
	buffer.writeu16(data, index, bit32.replace(word, value, shift, width))
end

local ROWS: { Row } = {
	{ name = "a valid packing", edge = "high", index = nil },
	{
		-- uses sits after slot's 3 bits and reload's 1, in 4 bits that hold past its 9
		name = "uses at 15",
		edge = "low",
		patch = function (data: buffer)
			set(data, 4, 4, 15)
		end,
		index = 3,
	},
	{
		-- shots' count sits at bit 8, in 2 bits that hold past its 2
		name = "three shots",
		edge = "low",
		patch = function (data: buffer)
			set(data, 8, 2, 3)
		end,
		index = 4,
	},
	{
		-- The first shot's class sits at bit 42, after its sequence, fraction and yaw
		name = "class 3",
		edge = "high",
		patch = function (data: buffer)
			set(data, 42, 2, 3)
		end,
		index = 8,
	},
	{
		-- The first shot's fraction packs above -100 in 8 bits, so 255 is 155, past its 100
		name = "fraction 155",
		edge = "high",
		patch = function (data: buffer)
			set(data, 18, 8, 255)
		end,
		index = 6,
	},
	{ name = "a byte short", edge = "high", length = 17, index = 10 }, -- offset's 32 bits run past 136
	{ name = "no bytes", edge = "high", length = 0, index = 1 },
	{ name = "a byte over", edge = "low", length = 11, index = PAST },
	{ name = "past the largest", edge = "high", length = 19, index = PAST },
	{
		-- The low values fill 74 bits, so bit 79 is padding
		name = "padding set",
		edge = "low",
		patch = function (data: buffer)
			set(data, 72, 8, bit32.replace(buffer.readu8(data, 9), 1, 7))
		end,
		index = PAST,
	},
}

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)

	for _, row: Row in ROWS do
		local data: buffer = buffer.create(64)
		local bytes: number = Fields.write(layout.command, (Game :: any)[row.edge].command, data, 0)
		if row.patch then
			row.patch(data)
		end

		local failed: number? = Fields.read(layout.command, data, 0, row.length or bytes, {})
		if failed ~= row.index then
			return false, `{row.name} was refused at field {failed}, where it fails at {row.index}`
		end
	end

	-- A read of a block that has no fields takes only no bytes
	local empty: any = Fields.compile({ command = {}, rules = {}, server = {}, slot = {}, held = {} })
	if Fields.read(empty.command, buffer.create(1), 0, 0, {}) ~= nil then
		return false, "An empty list refused its zero bytes"
	elseif Fields.read(empty.command, buffer.create(1), 0, 1, {}) ~= 1 then
		return false, "An empty list took a byte, where it fails one past its last field, at 1"
	end

	return true, nil
end
