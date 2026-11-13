--[[
    character:setDowned puts the body in the Downed posture from the next
    step, and out of it the step stands it up again where the standing hull
    has room; anything but a boolean is refused
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3
local TOLERANCE: number = 1e-5 -- Studs, inside a float32's step at a hull's height

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local character: any = server:create(rig.mock:addBot("Bot"), rig:at(0, 0))
	rig:tick(TICKS)

	character:setDowned(true)
	rig:tick(1)

	local downed: any = character:getState()
	if downed.posture ~= "Downed" then
		return false, `After setDowned(true) the posture reads {downed.posture}`
	elseif math.abs(downed.standingBox.size.Y - rig.shared.step.crouched) > TOLERANCE then
		return false, `A downed body's hull stands {downed.standingBox.size.Y} studs tall, not the crouched hull's`
	end

	character:setDowned(false)
	rig:tick(1)

	if character:getState().posture ~= "Stand" then
		return false, `Out of Downed with room overhead the posture reads {character:getState().posture}`
	elseif pcall(character.setDowned, character, 1) then
		return false, "setDowned took a number"
	end

	return true, nil
end
