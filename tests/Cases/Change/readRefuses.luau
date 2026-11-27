--[[
    Change.read refuses, naming itself, a base of 0 or 32 or more, a mask
    holding Y both as a step and whole, a change running past its data's
    end, and a baseline of another character than the change names
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local CHANGE: string = "src/Codec/Change.luau"
local ID_LOW: number = 0x25 -- Slot 37 generation 2's u16, its low byte first
local ID_HIGH: number = 0x20

type Row = { name: string, bytes: { number }, text: string }

local ROWS: { Row } = {
	{ name = "a base of 0", bytes = { ID_LOW, ID_HIGH, 0, 0 }, text = "base is 1 to 31" },
	{ name = "a base of 32", bytes = { ID_LOW, ID_HIGH, 32, 0 }, text = "base is 1 to 31" },
	{ name = "a base of 255", bytes = { ID_LOW, ID_HIGH, 255, 0 }, text = "base is 1 to 31" },
	{ name = "Y both ways", bytes = { ID_LOW, ID_HIGH, 3, 0x84, 0, 0, 0 }, text = "holds Y both" },
	{ name = "a header cut short", bytes = { ID_LOW, ID_HIGH, 3 }, text = "runs past" },
	{ name = "X cut short", bytes = { ID_LOW, ID_HIGH, 3, 1, 0x60 }, text = "runs past" },
	{ name = "another character", bytes = { ID_LOW + 1, ID_HIGH, 3, 0 }, text = "names a baseline of 8229" },
}

return function (): (boolean, string | nil)
	local Change: any = Environment.load(CHANGE)
	local baseline: buffer = buffer.create(16)
	buffer.writeu8(baseline, 0, ID_LOW)
	buffer.writeu8(baseline, 1, ID_HIGH)

	for _, row: Row in ROWS do
		local data: buffer = buffer.create(#row.bytes)
		for index: number, byte: number in row.bytes do
			buffer.writeu8(data, index - 1, byte)
		end

		local refused: boolean, why: string = Refuses(row.text, Change.read, data, 0, baseline, 0, buffer.create(16), 0)
		if not refused then
			return false, `{row.name} was read as a change: {why}`
		elseif not string.find(why, "Change.read", 1, true) then
			return false, `{row.name} was refused without naming Change.read: {why}`
		end
	end

	return true, nil
end
