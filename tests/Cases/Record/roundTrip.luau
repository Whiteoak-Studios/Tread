--[[
    The 16 B record round-trips each field at its edges and its quantum's
    step: slot and generation, X and Z across the ±8,192-stud bound, Y
    across -1,024 to 1,024, the platform index and its selector, yaw, pitch,
    the state word, and lean or the head offset in its last byte
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local RECORD: string = "src/Codec/Record.luau"
local STEP: number = 1 / 64 -- X's and Z's quantum
local HEIGHT_STEP: number = 1 / 32
local YAW_STEP: number = 2 * math.pi / 65536
local PITCH_STEP: number = (math.pi / 2) / 127
local CLOSE: number = 1e-9

type Row = { name: string, set: { [string]: any }, back: { [string]: any }? }

local ROWS: { Row } = {
	{ name = "at rest", set = {} },
	{ name = "the lowest slot and generation", set = { slot = 0, generation = 0 } },
	{ name = "the highest slot and generation", set = { slot = 4095, generation = 15 } },
	{ name = "the play bound's low edge", set = { position = vector.create(-8192, -1024, -8192) } },
	{
		name = "the highest X, Y and Z held",
		set = { position = vector.create(8192 - STEP, 1024 - HEIGHT_STEP, 8192 - STEP) },
	},
	{
		name = "a quantum's step from 0",
		set = { position = vector.create(STEP, HEIGHT_STEP, -STEP) },
	},
	{
		name = "the bound itself, clamped to the step below it",
		set = { position = vector.create(8192, 1024, 8192) },
		back = { position = vector.create(8192 - STEP, 1024 - HEIGHT_STEP, 8192 - STEP) },
	},
	{
		name = "past the bound, clamped",
		set = { position = vector.create(-9000, -2000, 9000) },
		back = { position = vector.create(-8192, -1024, 8192 - STEP) },
	},
	{ name = "the lowest platform", set = { platform = 1 } },
	{ name = "the highest platform", set = { platform = 127 } },
	{ name = "a platform across both top nibbles", set = { platform = 0x5A, headYaw = 75 } },
	{ name = "yaw's step", set = { yaw = YAW_STEP } },
	{ name = "yaw's top", set = { yaw = 2 * math.pi - YAW_STEP } },
	{ name = "yaw past a turn, wrapped", set = { yaw = 2 * math.pi + YAW_STEP }, back = { yaw = YAW_STEP } },
	{ name = "pitch at 90° up", set = { pitch = math.pi / 2 } },
	{ name = "pitch at 90° down", set = { pitch = -math.pi / 2 } },
	{ name = "pitch's step", set = { pitch = PITCH_STEP } },
	{ name = "pitch past 90°, clamped", set = { pitch = 2 }, back = { pitch = math.pi / 2 } },
	{ name = "the state word's top", set = { word = 65535 } },
	{ name = "lean at its limit", set = { lean = 20 } },
	{ name = "lean at its other limit", set = { lean = -20 } },
	{ name = "lean's step", set = { lean = 20 / 127 } },
	{ name = "the head offset at its cone", set = { headYaw = 75, headPitch = -75 } },
	{ name = "the head offset's step", set = { headYaw = -75 / 7, headPitch = 75 / 7 } },
	{ name = "the head offset in yaw alone", set = { headYaw = 75 / 7 * 3 } },
	{
		name = "the head offset past its cone, clamped",
		set = { headYaw = 200, headPitch = -200 },
		back = { headYaw = 75, headPitch = -75 },
	},
	{
		-- The server zeroes lean while the offset is set, so the last byte holds the offset
		name = "lean beside the head offset",
		set = { lean = 10, headPitch = 75 },
		back = { lean = 0 },
	},
}

return function (): (boolean, string | nil)
	local Record: any = Environment.load(RECORD)
	local data: buffer = buffer.create(20)

	for _, row: Row in ROWS do
		local record: { [string]: any } = Record.new()
		for key: string, value: any in row.set do
			record[key] = value
		end

		local expected: { [string]: any } = table.clone(record)
		for key: string, value: any in row.back or {} do
			expected[key] = value
		end

		buffer.fill(data, 0, 0xEE)
		Record.write(record, data, 2, Game.limits)
		if buffer.readu8(data, 1) ~= 0xEE or buffer.readu8(data, 18) ~= 0xEE then
			return false, `{row.name}: the record wrote outside its 16 B`
		end

		local into: { [string]: any } = Record.new()
		Record.read(data, 2, into, Game.limits)
		local differs: string? = Same(expected, into, row.name, CLOSE)
		if differs then
			return false, differs
		end
	end

	-- The bytes of one record laid out field by field
	local record: { [string]: any } = Record.new()
	record.slot, record.generation = 0x123, 0xA
	record.position = vector.create(-8192, -1024, 0)
	record.platform = 0x5A
	record.yaw = 0
	record.pitch = math.pi / 2
	record.word = 0xBEEF
	record.lean = -20

	Record.write(record, data, 0, Game.limits)
	local bytes: { number } = {}
	for index: number = 0, 15 do
		table.insert(bytes, buffer.readu8(data, index))
	end

	-- Slot and generation 0xA123; X 0 under platform's low nibble 0xA; Z 2 ^ 19 under its high 0x5; Y 0; yaw 0;
	-- pitch 127; the word; and lean -127, since the selector is clear
	local expected: { number } = { 0x23, 0xA1, 0, 0, 0xA0, 0, 0, 0x58, 0, 0, 0, 0, 127, 0xEF, 0xBE, 0x81 }
	for index: number, byte: number in expected do
		if bytes[index] ~= byte then
			return false, `Byte {index - 1} of the laid-out record is {bytes[index]}, where it is {byte}`
		end
	end

	-- A character's id is 12 bits of slot below 4 of generation
	local slot: number, generation: number = Record.split(Record.id(4095, 15))
	if Record.id(4095, 15) ~= 65535 or slot ~= 4095 or generation ~= 15 or Record.id(1, 1) ~= 4097 then
		return false, "A slot and generation's id isn't 12 bits of slot below 4 of generation"
	end

	return true, nil
end
