--[[
    Block.read refuses a change record past the block's end, with a base
    outside 1 to 31 or with a mask holding Y both ways, and a withheld
    block's reader refuses a change record, which only a relay block carries
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local ID_LOW: number = 0x25 -- Slot 37 generation 2's u16, its low byte first
local ID_HIGH: number = 0x20

type Row = { name: string, bytes: { number }, text: string }

-- A header with the sequence, tick and counts at 0 but the whole records'
local function header(records: number): { number }
	return { 0, 0, 0, 0, 0, 0, 0, 0, records }
end

local function join(...: { number }): { number }
	local joined: { number } = {}
	for _, part: { number } in { ... } do
		table.move(part, 1, #part, #joined + 1, joined)
	end

	return joined
end

local ROWS: { Row } = {
	{ name = "a change's header past the end", bytes = join(header(0), { ID_LOW, ID_HIGH, 3 }), text = "ends inside" },
	{
		name = "a change's X past the end",
		bytes = join(header(0), { ID_LOW, ID_HIGH, 3, 1, 0x60 }),
		text = "ends inside",
	},
	{
		name = "a change past the end behind a whole record",
		bytes = join(header(1), table.create(16, 0), { ID_LOW, ID_HIGH, 3, 2 }),
		text = "ends inside",
	},
	{ name = "a base of 0", bytes = join(header(0), { ID_LOW, ID_HIGH, 0, 0 }), text = "base is 1 to 31" },
	{ name = "a base of 32", bytes = join(header(0), { ID_LOW, ID_HIGH, 32, 0 }), text = "base is 1 to 31" },
	{
		name = "Y both ways",
		bytes = join(header(0), { ID_LOW, ID_HIGH, 3, 0x84, 0, 0, 0 }),
		text = "holds Y both as a step and whole",
	},
}

-- A buffer of the bytes given
local function bytesOf(bytes: { number }): buffer
	local data: buffer = buffer.create(#bytes)
	for index: number, byte: number in bytes do
		buffer.writeu8(data, index - 1, byte)
	end

	return data
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)

	for _, row: Row in ROWS do
		local refused: boolean, why: string = Refuses(row.text, Block.read, bytesOf(row.bytes), Block.new())
		if not refused then
			return false, `{row.name} was read as a block: {why}`
		end
	end

	-- A block of one whole record reads as a withheld block, and one with a still change beside it doesn't
	local whole: { number } = join(header(1), { ID_LOW, ID_HIGH }, table.create(14, 0))
	local changed: { number } = join(whole, { ID_LOW, ID_HIGH, 1, 0 })
	local version: number = Constants.CODEC_VERSION

	local withheld: any = Decode.decode(version, "withheld", bytesOf(whole))
	if #withheld.records ~= 1 or #withheld.changes ~= 0 then
		return false, "A withheld block of one whole record decoded with other records"
	end

	local refused: boolean, why: string =
		Refuses("no change records", Decode.decode, version, "withheld", bytesOf(changed))
	if not refused then
		return false, `A withheld block with a change record was decoded: {why}`
	end

	local relay: any = Decode.decode(version, "relay", bytesOf(changed))
	if #relay.records ~= 1 or #relay.changes ~= 1 then
		return false, "The same bytes didn't decode as a relay block of one whole record and one change"
	end

	return true, nil
end
