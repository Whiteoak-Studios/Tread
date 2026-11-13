--[[
    Bits refuses a value its width doesn't hold, a width past 32, a write
    past its stretch and a cursor past its buffer, and a read past the end
    gives nil
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local BITS: string = "src/Codec/Bits.luau"

type Row = { text: string, call: () -> () }

return function (): (boolean, string | nil)
	local Bits: any = Environment.load(BITS)
	local data: buffer = buffer.create(2)

	local function writes(value: number, width: number): () -> ()
		return function ()
			Bits.write(Bits.writer(data, 0, 2), value, width)
		end
	end

	local rows: { Row } = {
		{ text = "is no whole number", call = writes(8, 3) },
		{ text = "is no whole number", call = writes(-1, 3) },
		{ text = "is no whole number", call = writes(1.5, 3) },
		{ text = "is no whole number", call = writes(0 / 0, 3) },
		{ text = "doesn't fit in 0 bits", call = writes(1, 0) },
		{ text = "passes its cursor's", call = writes(1, 33) },
		{ text = "passes its cursor's", call = writes(1, 17) },
		{
			text = "passes the end",
			call = function ()
				Bits.writer(data, 1, 2)
			end,
		},
		{
			text = "wider than",
			call = function ()
				Bits.read(Bits.reader(data, 0, 2), 33)
			end,
		},
	}

	for index: number, row: Row in rows do
		local refused: boolean, why: string = Refuses(row.text, row.call)
		if not refused then
			return false, `Refusal {index} wasn't made: {why}`
		end
	end

	-- A cursor's own stretch bounds it even when its buffer goes on
	local cursor: any = Bits.writer(data, 0, 1)
	Bits.write(cursor, 255, 8)
	local refused: boolean, why: string = Refuses("passes its cursor's", Bits.write, cursor, 1, 1)
	if not refused then
		return false, `A write past a cursor's stretch inside its buffer wasn't refused: {why}`
	end

	local reader: any = Bits.reader(data, 0, 1)
	if Bits.read(reader, 9) ~= nil or reader.bit ~= 0 then
		return false, "A read past a stretch gave a value, or moved the cursor"
	end

	return true, nil
end
