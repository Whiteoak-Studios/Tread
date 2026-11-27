--[[
    Public.look turns the base look by the head offset held to the cone:
    an offset at the cone's edges turns it by the edge, one past them by
    the edge too and one inside as given, bit for bit on the step's own trig
--]]

--!strict
local Environment = require("../../Environment")

local PUBLIC: string = "src/Step/Public.luau"
local MATH: string = "src/Step/Math.luau"
local CONSTANTS: string = "src/Constants.luau"

local CONE: number = 75 -- Frontier Zero's step.headCone, in degrees
local YAW: number = 0.4 -- The base look, radians, low enough that no offset reaches the pitch limit
local PITCH: number = 0.1
local CLOSE: number = 1e-6 -- A vector holds float32s, so a look's components agree to about 1e-7

type Row = {
	headYaw: number,
	headPitch: number,
	cone: number?, -- The cone, CONE unless given
	same: number?, -- The row whose look this one's must equal exactly
}

local ROWS: { Row } = {
	{ headYaw = CONE, headPitch = -CONE }, -- 1: at the cone's edges
	{ headYaw = -CONE, headPitch = CONE }, -- 2: at the other edges
	{ headYaw = 120, headPitch = -100, same = 1 }, -- Past the edges of row 1
	{ headYaw = -200, headPitch = 90, same = 2 }, -- Past those of row 2
	{ headYaw = 30, headPitch = -20 }, -- Inside the cone
	{ headYaw = 0, headPitch = 0 }, -- 6: no offset
	{ headYaw = 50, headPitch = -40, cone = 0, same = 6 }, -- A cone of 0 holds every offset to none
}

return function (): (boolean, string | nil)
	local Public: any = Environment.load(PUBLIC)
	local Math: any = Environment.load(MATH)
	local Constants: any = Environment.load(CONSTANTS)
	local limit: number = Constants.PITCH_LIMIT / Constants.ANGLE_STEPS * (2 * math.pi)

	-- The look written out: the offset held to the cone, the pitch to a quarter turn, then the step's sine and cosine
	local function expected(headYaw: number, headPitch: number, cone: number): vector
		local yaw: number = YAW + math.rad(math.clamp(headYaw, -cone, cone))
		local pitch: number = math.clamp(PITCH + math.rad(math.clamp(headPitch, -cone, cone)), -limit, limit)
		local level: number = Math.cos(pitch)

		return vector.create(-Math.sin(yaw) * level, Math.sin(pitch), -Math.cos(yaw) * level)
	end

	local looks: { vector } = {}

	for index: number, row: Row in ROWS do
		local cone: number = row.cone or CONE
		local look: vector = Public.look(YAW, PITCH, row.headYaw, row.headPitch, cone)
		looks[index] = look

		local want: vector = expected(row.headYaw, row.headPitch, cone)
		if look ~= want then
			return false, `Row {index}'s look was {look}, where the written-out math gives {want}`
		end

		local length: number = vector.magnitude(look)
		if math.abs(length - 1) > CLOSE then
			return false, `Row {index}'s look was {length} long, not a unit vector`
		end

		local same: number? = row.same
		if same and look ~= looks[same] then
			return false, `Row {index}'s look was {look}, not row {same}'s {looks[same]}, which it clamps to`
		end
	end

	-- The edge row turned by the C library's trig, so the look turns the right way and by the right amount
	local yaw: number, pitch: number = YAW + math.rad(CONE), PITCH - math.rad(CONE)
	local level: number = math.cos(pitch)
	local edge: vector = vector.create(-math.sin(yaw) * level, math.sin(pitch), -math.cos(yaw) * level)
	local apart: vector = looks[1] - edge
	if math.abs(apart.x) > CLOSE or math.abs(apart.y) > CLOSE or math.abs(apart.z) > CLOSE then
		return false, `At the cone's edges the look was {looks[1]}, not {edge}`
	end

	return true, nil
end
