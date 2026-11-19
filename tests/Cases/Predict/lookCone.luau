--[[
    The eye's look turns by the game's head offset, held to the game's cone
    as the step holds a command's: 120° and -100° of offset turn the look by
    the cone's 75° and -75°, and one inside the cone turns it as given
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local CONE: number = 75 -- Frontier Zero's step.headCone, in degrees
local CLOSE: number = 1e-6 -- A vector holds float32s, so a look's components agree to about 1e-7

type Row = { headYaw: number, headPitch: number, yaw: number, pitch: number }

local ROWS: { Row } = {
	{ headYaw = 120, headPitch = -100, yaw = CONE, pitch = -CONE }, -- Past the cone either way
	{ headYaw = -30, headPitch = 20, yaw = -30, pitch = 20 }, -- Inside it
}

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()

	for _, row: Row in ROWS do
		rig.view.headYaw = row.headYaw
		rig.view.headPitch = row.headPitch
		rig.frames(1, 0)

		local _, look: vector = rig.Predict.eye()
		local yaw: number, pitch: number = math.rad(row.yaw), math.rad(row.pitch)
		local level: number = math.cos(pitch)
		local want: vector = vector.create(-math.sin(yaw) * level, math.sin(pitch), -math.cos(yaw) * level)
		local apart: vector = look - want

		if math.abs(apart.x) > CLOSE or math.abs(apart.y) > CLOSE or math.abs(apart.z) > CLOSE then
			local offset: string = `{row.headYaw}° and {row.headPitch}°`
			local turned: string = `{row.yaw}° and {row.pitch}°`
			return false, `A head offset of {offset} published a look of {look}, not one turned {turned}`
		end
	end

	return true, nil
end
