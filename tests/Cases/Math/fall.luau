--[[
    Math.fall's place and fraction at the start, half way, the end and past
    it, and an end time of 0 for a move that is level or upward
--]]

--!strict
local Environment = require("../../Environment")

local MATH: string = "src/Step/Math.luau"
local GRAVITY: number = 68.1 -- Frontier Zero's step.gravity
local TOLERANCE: number = 1e-9

type Row = { name: string, elapsed: number, place: vector, fraction: number }

local function apart(a: vector, b: vector): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y), math.abs(a.z - b.z))
end

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)

	local from: vector = vector.create(4, 1120, -6)
	local to: vector = vector.create(10, 1100, 2)
	local drop: number = from.y - to.y
	local duration: number = math.sqrt(2 * drop / GRAVITY) -- From drop = gravity * duration² / 2

	local rows: { Row } = {
		{ name = "at the start", elapsed = 0, place = from, fraction = 0 },
		{
			-- Half the time covers half the way across and a quarter of the drop
			name = "half way",
			elapsed = duration / 2,
			place = vector.create((from.x + to.x) / 2, from.y - drop / 4, (from.z + to.z) / 2),
			fraction = 0.5,
		},
		{ name = "at the end", elapsed = duration, place = to, fraction = 1 },
		{ name = "past the end", elapsed = duration * 2, place = to, fraction = 1 },
	}

	for _, row: Row in rows do
		local place: vector, fraction: number = Math.fall(from, to, GRAVITY, row.elapsed)
		if apart(place, row.place) > TOLERANCE or math.abs(fraction - row.fraction) > TOLERANCE then
			local found: string = `Math.fall {row.name} gave {place} at {fraction}`

			return false, `{found}, where {row.place} at {row.fraction} was expected`
		end
	end

	-- A move whose new place is not below the old shows at once, so it ends at an elapsed time of 0
	local level: vector = vector.create(10, from.y, 2)
	local upward: vector = vector.create(10, from.y + 5, 2)

	for _, target: vector in { level, upward } do
		local place: vector, fraction: number = Math.fall(from, target, GRAVITY, 0)
		if place ~= target or fraction ~= 1 then
			return false, `Math.fall to {target}, not below {from}, gave {place} at {fraction} at once, not its end`
		end
	end

	return true, nil
end
