--[[
    Block.read refuses bytes that aren't a relay block: shorter than its
    header, past 896 B, a section past the end, records that aren't whole,
    a kind code no kind has, a look flag no part has or a part past its bound,
    and a footstep entry naming no kind or material
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local BLOCK: string = "src/Codec/Block.luau"

type Row = { name: string, bytes: { number }, text: string }

-- A header with the sequence and tick at 0 and the four counts given
local function header(reveals: number, hides: number, looks: number, footsteps: number): { number }
	return { 0, 0, 0, 0, reveals, hides, looks, footsteps }
end

local function join(...: { number }): { number }
	local joined: { number } = {}
	for _, part: { number } in { ... } do
		table.move(part, 1, #part, #joined + 1, joined)
	end

	return joined
end

local ROWS: { Row } = {
	{ name = "7 B", bytes = { 0, 0, 0, 0, 0, 0, 0 }, text = "8 to 896 B, not 7" },
	{ name = "a reveal past the end", bytes = join(header(1, 0, 0, 0), { 1, 0 }), text = "ends inside" },
	{ name = "a reveal of kind 4", bytes = join(header(1, 0, 0, 0), { 1, 0, 4 }), text = "kind code 4" },
	{ name = "a hide past the end", bytes = join(header(0, 1, 0, 0), { 1 }), text = "ends inside" },
	{ name = "a look flag of 4", bytes = join(header(0, 0, 1, 0), { 1, 0, 4 }), text = "flags 4" },
	{ name = "a look of 65 B", bytes = join(header(0, 0, 1, 0), { 1, 0, 1, 65 }), text = "part of 65 B" },
	{ name = "a held item of 17 B", bytes = join(header(0, 0, 1, 0), { 1, 0, 2, 17 }), text = "part of 17 B" },
	{ name = "a look past the end", bytes = join(header(0, 0, 1, 0), { 1, 0, 1, 4, 0 }), text = "ends inside" },
	{ name = "a footstep past the end", bytes = join(header(0, 0, 0, 1), table.create(9, 0)), text = "ends inside" },
	{ name = "a record cut short", bytes = join(header(0, 0, 0, 0), table.create(17, 0)), text = "1 B into a record" },
}

return function (): (boolean, string | nil)
	local Block: any = Environment.load(BLOCK)

	for _, row: Row in ROWS do
		local data: buffer = buffer.create(#row.bytes)
		for index: number, byte: number in row.bytes do
			buffer.writeu8(data, index - 1, byte)
		end

		local refused: boolean, why: string = Refuses(row.text, Block.read, data, Block.new())
		if not refused then
			return false, `{row.name} was read as a block: {why}`
		end
	end

	local refused: boolean, why: string = Refuses("not 897", Block.read, buffer.create(897), Block.new())
	if not refused then
		return false, `A block of 897 B was read: {why}`
	end

	-- A footstep entry with a kind code past Land, and one with an Enum value no material has
	local step: buffer = buffer.create(10)
	local into: { [string]: any } = { at = vector.zero, kind = "Walk", material = nil }
	buffer.writeu8(step, 2, 0x48)
	refused, why = Refuses("no value is given", Block.readFootstep, step, 0, into)
	if not refused then
		return false, `A footstep of kind code 4 was read: {why}`
	end

	buffer.writeu8(step, 2, 0)
	buffer.writeu16(step, 8, 65535)
	refused, why = Refuses("no value is given", Block.readFootstep, step, 0, into)
	if not refused then
		return false, `A footstep of no material was read: {why}`
	end

	return true, nil
end
