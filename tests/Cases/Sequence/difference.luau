--[[
    Sequence.difference gives the signed wrap-safe difference of two u16
    wire numbers, from -32,768 to 32,767, across the wrap and at its edges,
    and the shortest arc between two yaws
--]]

--!strict
local Environment = require("../../Environment")

local SEQUENCE: string = "src/Codec/Sequence.luau"

type Row = { a: number, b: number, difference: number }

local ROWS: { Row } = {
	{ a = 5, b = 3, difference = 2 },
	{ a = 3, b = 5, difference = -2 },
	{ a = 9, b = 9, difference = 0 },
	{ a = 0, b = 65535, difference = 1 }, -- Across the wrap, newer
	{ a = 65535, b = 0, difference = -1 },
	{ a = 2, b = 65530, difference = 8 },
	{ a = 32767, b = 0, difference = 32767 }, -- The newest a can be
	{ a = 32768, b = 0, difference = -32768 }, -- Half the wrap away reads as older
	{ a = 0, b = 32768, difference = -32768 },
	{ a = 65535, b = 32768, difference = 32767 },
	{ a = 100, b = 65500, difference = 136 }, -- Yaw steps either side of 0 take the short way round
	{ a = 65500, b = 100, difference = -136 },
}

return function (): (boolean, string | nil)
	local Sequence: any = Environment.load(SEQUENCE)

	for _, row: Row in ROWS do
		local difference: number = Sequence.difference(row.a, row.b)
		if difference ~= row.difference then
			return false, `difference({row.a}, {row.b}) is {difference}, where it is {row.difference}`
		end
	end

	-- Every difference stays in range, and a compare reads newer one way only
	for a: number = 0, 65535, 257 do
		for b: number = 0, 65535, 263 do
			local forward: number = Sequence.difference(a, b)
			local back: number = Sequence.difference(b, a)

			if forward < -32768 or forward > 32767 then
				return false, `difference({a}, {b}) is {forward}, outside -32,768 to 32,767`
			elseif forward > 0 and back > 0 then
				return false, `{a} and {b} each read as newer than the other`
			end
		end
	end

	return true, nil
end
