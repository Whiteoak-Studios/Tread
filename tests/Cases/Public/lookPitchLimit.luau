--[[
    Public.look holds the pitch to a quarter turn either way: a head offset
    or a base pitch that would take it past looks straight up or down, as
    the limit itself does, while a pitch under the limit is left as it is
--]]

--!strict
local Environment = require("../../Environment")

local PUBLIC: string = "src/Step/Public.luau"

local CONE: number = 75 -- Frontier Zero's step.headCone, in degrees
local YAW: number = 1.1 -- Radians, so a look's level part would show off the vertical
local QUARTER: number = math.pi / 2 -- The pitch limit, straight up
local UNDER: number = QUARTER - 0.1 -- A base pitch under it, which the cone's head pitch takes past it
local PAST: number = 2 -- A base pitch past it with no offset at all
local CLOSE: number = 1e-6 -- A vector holds float32s, so a look's components agree to about 1e-7
local NONE: number = 0 -- A head offset of none, in degrees
local UP: vector = vector.create(0, 1, 0)
local DOWN: vector = vector.create(0, -1, 0)

type Row = { pitch: number, headPitch: number, want: vector, label: string }

local ROWS: { Row } = {
	{ pitch = QUARTER, headPitch = 0, want = UP, label = "a pitch at the limit" },
	{ pitch = -QUARTER, headPitch = 0, want = DOWN, label = "a pitch at the limit below" },
	{ pitch = UNDER, headPitch = CONE, want = UP, label = "a head pitch taking the look past the limit" },
	{ pitch = -UNDER, headPitch = -CONE, want = DOWN, label = "a head pitch taking it past the limit below" },
	{ pitch = PAST, headPitch = 0, want = UP, label = "a base pitch past the limit" },
	{ pitch = -PAST, headPitch = -CONE, want = DOWN, label = "a base pitch and head pitch both past it below" },
}

return function (): (boolean, string | nil)
	local Public: any = Environment.load(PUBLIC)

	-- Straight up or down exactly, since the step's cosine of a quarter turn is 0
	for _, row: Row in ROWS do
		local look: vector = Public.look(YAW, row.pitch, NONE, row.headPitch, CONE)
		if look ~= row.want then
			return false, `With {row.label} the look was {look}, not {row.want}`
		end
	end

	-- Under the limit the pitch stands, so the look keeps its level part along the yaw
	local under: vector = Public.look(YAW, UNDER, NONE, NONE, CONE)
	local level: number = math.cos(UNDER)
	local want: vector = vector.create(-math.sin(YAW) * level, math.sin(UNDER), -math.cos(YAW) * level)
	local apart: vector = under - want
	if math.abs(apart.x) > CLOSE or math.abs(apart.y) > CLOSE or math.abs(apart.z) > CLOSE then
		return false, `A pitch under the limit gave a look of {under}, not {want}`
	end

	return true, nil
end
