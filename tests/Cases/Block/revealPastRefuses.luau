--[[
    A reveal's past is refused on write past 7 records, on any reveal but a
    player's or with no place named, and on read for each way its bytes
    break the layout, in the order the reader checks them
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLOT: number = 10
local GENERATION: number = 3
local AGES: { number } = { 3, 1 } -- The valid block's past, oldest first

-- Where the valid block keeps its reveal's kind byte and each past record's age and character
local KIND_AT: number = 11
local FIRST_AGE_AT: number = 12
local FIRST_ID_AT: number = 13
local SECOND_AGE_AT: number = 29
local SECOND_ID_AT: number = 30

type Row = { name: string, text: string, cut: number?, change: (data: buffer) -> () }

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Constants: any = globals.require(tread.Constants)
	local Record: any = globals.require(tread.Codec.Record)
	local entry: number = Constants.PAST_BYTES

	-- A pool of 8 past records of the slot, ages falling from 8 to 1, the first two the valid block's
	local pool: buffer = buffer.create(8 * entry)
	for index: number = 1, 8 do
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = SLOT, GENERATION
		record.position = vector.create(index, 0, -index)
		buffer.writeu8(pool, (index - 1) * entry, AGES[index] or 9 - index)
		Record.write(record, pool, (index - 1) * entry + 1, Game.limits)
	end

	-- A block of one reveal of kind with the past named
	local function made(kind: string, count: number?, at: number?, data: buffer?): any
		local block: any = Block.new()
		block.reveals[1] = { slot = SLOT, generation = GENERATION, kind = kind, pastCount = count, pastAt = at }
		block.revealCount = 1
		block.pastData = data

		return block
	end

	-- The writer's refusals
	local room: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local writes: { { any } } = {
		{ "a past of 8", "0 to 7 past records, not 8", made("Player", 8, 0, pool) },
		{ "a past of -1", "0 to 7 past records, not -1", made("Player", -1, 0, pool) },
		{ "an Npc's past", "not this Npc's", made("Npc", 1, 0, pool) },
		{ "a Body's past", "not this Body's", made("Body", 1, 0, pool) },
		{ "a Sleeper's past", "not this Sleeper's", made("Sleeper", 1, 0, pool) },
		{ "a past at no place", "names no such place", made("Player", 2, nil, pool) },
		{ "a past in no pool", "names no such place", made("Player", 2, 0, nil) },
	}

	for _, row: { any } in writes do
		local refused: boolean, why: string = Refuses(row[2], Block.write, row[3], room)
		if not refused then
			return false, `{row[1]} was written: {why}`
		end
	end

	-- The valid block: a player's reveal with its past of two, which reads back whole
	local bytes: number = Block.write(made("Player", #AGES, 0, pool), room)
	if bytes ~= 9 + 3 + #AGES * entry then
		return false, `The valid block filled {bytes} B, not {9 + 3 + #AGES * entry}`
	end

	local valid: buffer = buffer.create(bytes)
	buffer.copy(valid, 0, room, 0, bytes)

	local own: number = Record.id(SLOT, GENERATION)
	local other: number = Record.id(SLOT + 1, GENERATION)
	local later: number = Record.id(SLOT, GENERATION + 1)

	local read: any = Block.new()
	Block.read(valid, read)
	if read.reveals[1].pastCount ~= #AGES or buffer.readu8(valid, KIND_AT) ~= 0x40 then
		return false, `The valid block read back a past of {read.reveals[1].pastCount}`
	elseif buffer.readu8(valid, SECOND_AGE_AT) ~= AGES[2] or buffer.readu16(valid, FIRST_ID_AT) ~= own then
		return false, "The valid block's past records aren't where the rows below change them"
	end

	local function kind(byte: number): (data: buffer) -> ()
		return function (data: buffer)
			buffer.writeu8(data, KIND_AT, byte)
		end
	end

	local function ages(first: number, second: number): (data: buffer) -> ()
		return function (data: buffer)
			buffer.writeu8(data, FIRST_AGE_AT, first)
			buffer.writeu8(data, SECOND_AGE_AT, second)
		end
	end

	-- The reader's refusals, each row after the first of a kind also showing which check comes before it
	local rows: { Row } = {
		{ name = "a kind code of 4 under a past of 2", text = "kind code 4 has no kind", change = kind(0x44) },
		{ name = "a kind code of 31 under a past of 7", text = "kind code 31 has no kind", change = kind(0xFF) },
		{ name = "a Sleeper's past", text = "this Sleeper's carries 2", change = kind(0x43) },
		{ name = "a Body's past", text = "this Body's carries 2", change = kind(0x42) },
		{ name = "an Npc's past cut short", text = "this Npc's carries 2", cut = 1, change = kind(0x41) },
		{ name = "a past cut short", text = "ends inside the entry at byte 12", cut = 1, change = ages(3, 1) },
		{ name = "a past of 7 with 2 records", text = "ends inside the entry at byte 12", change = kind(0xE0) },
		{ name = "a past cut short with an age of 0", text = "ends inside", cut = 1, change = ages(0, 1) },
		{ name = "an age of 0", text = "1 to 31 relay ticks old, not 0", change = ages(0, 1) },
		{ name = "an age of 32", text = "1 to 31 relay ticks old, not 32", change = ages(32, 1) },
		{ name = "an age of 255", text = "1 to 31 relay ticks old, not 255", change = ages(255, 1) },
		{ name = "a second age of 0", text = "1 to 31 relay ticks old, not 0", change = ages(3, 0) },
		{ name = "ages that hold", text = "one 3 ticks old follows one 3 old", change = ages(3, 3) },
		{ name = "ages that rise", text = "one 3 ticks old follows one 1 old", change = ages(1, 3) },
		{
			name = "another slot's record",
			text = `names character {other}, not its own {own}`,
			change = function (data: buffer)
				buffer.writeu16(data, SECOND_ID_AT, other)
			end,
		},
		{
			name = "another generation's record",
			text = `names character {later}, not its own {own}`,
			change = function (data: buffer)
				buffer.writeu16(data, FIRST_ID_AT, later)
			end,
		},
		{
			name = "an age of 0 on another slot's record",
			text = "not 0",
			change = function (data: buffer)
				buffer.writeu8(data, FIRST_AGE_AT, 0)
				buffer.writeu16(data, FIRST_ID_AT, other)
			end,
		},
		{
			name = "a rising age on another slot's record",
			text = "follows one 1 old",
			change = function (data: buffer)
				ages(1, 3)(data)
				buffer.writeu16(data, SECOND_ID_AT, other)
			end,
		},
	}

	for _, row: Row in rows do
		local data: buffer = buffer.create(bytes - (row.cut or 0))
		buffer.copy(data, 0, valid, 0, buffer.len(data))
		row.change(data)

		local refused: boolean, why: string = Refuses(row.text, Block.read, data, Block.new())
		if not refused then
			return false, `{row.name} was read as a block: {why}`
		end
	end

	return true, nil
end
