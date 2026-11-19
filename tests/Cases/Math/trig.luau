--[[
    Math.sin and Math.cos stay within their stated bound of the C library's
    at every u16 angle of the turn either way, are exact at 0, and give the
    same bits each time for the same angle
--]]

--!strict
local Environment = require("../../Environment")

local MATH: string = "src/Step/Math.luau"
local CONSTANTS: string = "src/Constants.luau"
local BOUND: number = 5e-16 -- The most either may differ from the C library's, across the turn
local TURN: number = 2 * math.pi
local F64_BYTES: number = 8

-- The bits of a number, so a -0 and a 0 count as different
local function bits(value: number): string
	local bytes: buffer = buffer.create(F64_BYTES)
	buffer.writef64(bytes, 0, value)

	return buffer.tostring(bytes)
end

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)
	local steps: number = Environment.load(CONSTANTS).ANGLE_STEPS

	local worst: number = 0
	local worstAt: number = 0

	-- Every angle a u16 holds, then the same turned the other way
	for step: number = -steps, steps do
		local angle: number = step / steps * TURN
		local sine: number = Math.sin(angle)
		local cosine: number = Math.cos(angle)
		local gap: number = math.max(math.abs(sine - math.sin(angle)), math.abs(cosine - math.cos(angle)))

		if gap > worst then
			worst = gap
			worstAt = angle
		end

		if bits(Math.sin(angle)) ~= bits(sine) or bits(Math.cos(angle)) ~= bits(cosine) then
			return false, `Math.sin or Math.cos of {angle} gave other bits the second time`
		end
	end

	if worst > BOUND then
		return false, `Math.sin or Math.cos differs from the C library's by {worst} at {worstAt}, past {BOUND}`
	end

	if bits(Math.sin(0)) ~= bits(0) or Math.cos(0) ~= 1 then
		return false, `Math.sin(0) gave {Math.sin(0)} and Math.cos(0) gave {Math.cos(0)}, where 0 and 1 were expected`
	end

	return true, nil
end
