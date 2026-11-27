--[[
    A body is hit through Downed's shapes whenever it lies, through Crouch's
    whenever it swims and doesn't lie, downed or not, and otherwise through
    its own posture's, in every other mode
--]]

--!strict
local Environment = require("../../Environment")

local SHAPES: string = "src/Step/Shapes.luau"

local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local MODES: { string } = { "Ground", "Air", "Swim", "Ladder", "Mantle" }

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)

	for _, posture: string in POSTURES do
		for _, mode: string in MODES do
			local lying: string = Shapes.posture(posture, mode, true)
			local standing: string = Shapes.posture(posture, mode, false)
			local want: string = mode == "Swim" and "Crouch" or posture

			if lying ~= "Downed" then
				return false, `A lying body, {posture} in {mode}, is hit through {lying}, not Downed`
			elseif standing ~= want then
				return false, `A body not lying, {posture} in {mode}, is hit through {standing}, not {want}`
			end
		end
	end

	return true, nil
end
