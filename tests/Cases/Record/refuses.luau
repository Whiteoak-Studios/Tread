--[[
    A record refuses a slot past 12 bits, a generation past 4 and a platform
    past the 127 its 7 bits hold, rather than writing one that names another
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local RECORD: string = "src/Codec/Record.luau"

type Row = { key: string, value: number, text: string }

local ROWS: { Row } = {
	{ key = "slot", value = 4096, text = "don't fit" },
	{ key = "slot", value = -1, text = "don't fit" },
	{ key = "slot", value = 1.5, text = "don't fit" },
	{ key = "generation", value = 16, text = "don't fit" },
	{ key = "platform", value = 128, text = "platform is 0 to 127" },
	{ key = "platform", value = -1, text = "platform is 0 to 127" },
}

return function (): (boolean, string | nil)
	local Record: any = Environment.load(RECORD)
	local data: buffer = buffer.create(16)

	for _, row: Row in ROWS do
		local record: { [string]: any } = Record.new()
		record[row.key] = row.value

		local refused: boolean, why: string = Refuses(row.text, Record.write, record, data, 0, Game.limits)
		if not refused then
			return false, `A record with {row.key} {row.value} was written: {why}`
		end
	end

	return true, nil
end
