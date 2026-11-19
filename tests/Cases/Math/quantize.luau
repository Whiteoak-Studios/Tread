--[[
    The quantizers round to OwnerState's precisions, a position to 1/512 stud,
    a velocity to 1/64 and the eye to 1/32, halves away from zero both ways
--]]

--!strict
local Environment = require("../../Environment")

local MATH: string = "src/Step/Math.luau"

type Row = { name: string, value: number, want: number }

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)

	local position: { Row } = {
		{ name = "a whole quantum", value = 3 / 512, want = 3 / 512 },
		{ name = "under half a quantum", value = 0.0009, want = 0 },
		{ name = "half a quantum", value = 1 / 1024, want = 1 / 512 },
		{ name = "half a quantum below 0", value = -1 / 1024, want = -1 / 512 },
		{ name = "a far coordinate", value = 8191.9993, want = 8192 },
	}

	local velocity: { Row } = {
		{ name = "a whole step", value = 5 / 64, want = 5 / 64 },
		{ name = "half a step", value = 1 / 128, want = 1 / 64 },
		{ name = "a fall", value = -138.9, want = -8890 / 64 },
	}

	local eye: { Row } = {
		{ name = "the standing eye", value = 4.17, want = 133 / 32 },
		{ name = "half a step", value = 1 / 64, want = 1 / 32 },
	}

	local quantizers: { [string]: { Row } } = {
		quantize = position,
		quantizeVelocity = velocity,
		quantizeEye = eye,
	}

	for name: string, rows: { Row } in quantizers do
		for _, row: Row in rows do
			local got: number = Math[name](row.value)
			if got ~= row.want then
				return false, `Math.{name} of {row.name}, {row.value}, gave {got}, where {row.want} was expected`
			end
		end
	end

	return true, nil
end
