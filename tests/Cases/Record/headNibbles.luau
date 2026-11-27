--[[
    A record's last byte holds the head offset as two signed 4-bit levels,
    yaw in the low nibble and pitch in the high one, each 7 steps to the
    cone, and the selector bit at the top of Z says it does
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local RECORD: string = "src/Codec/Record.luau"
local LAST_BYTE: number = 15
local Z_TOP_BYTE: number = 7 -- Z's u24 top byte, whose top bit is the selector
local SELECTOR_BIT: number = 7
local LEVEL: number = 75 / 7 -- One level, at the fixture's 75° cone
local CLOSE: number = 1e-9

type Row = { name: string, headYaw: number, headPitch: number, byte: number }

local ROWS: { Row } = {
	{ name = "yaw at -7 and pitch at 7", headYaw = -75, headPitch = 75, byte = 0x79 },
	{ name = "yaw at 1 and pitch at -1", headYaw = LEVEL, headPitch = -LEVEL, byte = 0xF1 },
	{ name = "pitch alone at -3", headYaw = 0, headPitch = -3 * LEVEL, byte = 0xD0 },
	{ name = "yaw alone past the cone, clamped to -7", headYaw = -200, headPitch = 0, byte = 0x09 },
}

return function (): (boolean, string | nil)
	local Record: any = Environment.load(RECORD)
	local data: buffer = buffer.create(16)

	for _, row: Row in ROWS do
		local record: { [string]: any } = Record.new()
		record.headYaw = row.headYaw
		record.headPitch = row.headPitch
		Record.write(record, data, 0, Game.limits)

		local byte: number = buffer.readu8(data, LAST_BYTE)
		if byte ~= row.byte then
			return false, `{row.name}: the last byte is {byte}, where its nibbles make {row.byte}`
		elseif bit32.extract(buffer.readu8(data, Z_TOP_BYTE), SELECTOR_BIT) ~= 1 then
			return false, `{row.name}: the selector is clear while the last byte holds the head offset`
		end
	end

	-- A last byte laid out by hand reads back as its two levels: yaw 0xE, -2, and pitch 0x2, 2
	buffer.writeu8(data, LAST_BYTE, 0x2E)
	local into: { [string]: any } = Record.new()
	Record.read(data, 0, into, Game.limits)

	if math.abs(into.headYaw + 2 * LEVEL) > CLOSE or math.abs(into.headPitch - 2 * LEVEL) > CLOSE then
		return false, `The last byte 0x2E read as yaw {into.headYaw} and pitch {into.headPitch}, not -2 and 2 levels`
	elseif into.lean ~= 0 then
		return false, `The last byte read as the head offset, yet lean read {into.lean}`
	end

	return true, nil
end
