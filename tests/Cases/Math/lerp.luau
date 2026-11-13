--[[
    Math.lerp gives a + (b - a) * t in plain arithmetic at its ends, between
    them and past them, and is not math.lerp, whose exact end it misses
--]]

--!strict
local Environment = require("../../Environment")

local MATH: string = "src/Step/Math.luau"
local PLAIN_A: number = -0.3 -- An input whose plain form misses b by its last bit at t = 1
local PLAIN_B: number = 0.9

type Row = { a: number, b: number, t: number, want: number }

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)

	local rows: { Row } = {
		{ a = 2, b = 6, t = 0, want = 2 },
		{ a = 2, b = 6, t = 0.25, want = 3 },
		{ a = 2, b = 6, t = 1, want = 6 },
		{ a = -1, b = 1, t = 0.5, want = 0 },
		{ a = 4, b = -4, t = 1.5, want = -8 }, -- Past b, as a lerp carries on
		{ a = PLAIN_A, b = PLAIN_B, t = 1, want = PLAIN_A + (PLAIN_B - PLAIN_A) * 1 },
	}

	for _, row: Row in rows do
		local got: number = Math.lerp(row.a, row.b, row.t)
		if got ~= row.want then
			return false, `Math.lerp({row.a}, {row.b}, {row.t}) gave {got}, where {row.want} was expected`
		end
	end

	-- math.lerp lands exactly on b at t = 1, and native code fuses it, so the plain form must not
	if Math.lerp(PLAIN_A, PLAIN_B, 1) == PLAIN_B then
		return false, `Math.lerp({PLAIN_A}, {PLAIN_B}, 1) landed exactly on {PLAIN_B}, as math.lerp does`
	end

	return true, nil
end
