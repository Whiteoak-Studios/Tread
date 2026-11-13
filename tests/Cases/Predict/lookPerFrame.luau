--[[
    The eye's look comes from the game's look once a frame, so a turn
    between two ticks shows in the same frame, with no tick run and no
    sample taken, while the drawn body's facing keeps to its ticks
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local QUARTER: number = math.pi / 2 -- A yaw that looks along -X
local CLOSE: number = 1e-6 -- A vector holds float32s, so a look's components agree to about 1e-7

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(2)

	if rig.looks ~= 2 then
		return false, `Two frames read the game's look {rig.looks} times, not once each`
	end

	local _, ahead: vector = rig.Predict.eye()
	if math.abs(ahead.z + 1) > CLOSE or math.abs(ahead.x) > CLOSE then
		return false, `A level look ahead published {ahead}, not along -Z`
	end

	-- A quarter turn and a look up a sixth of a turn, a third of the way to the next tick
	rig.view.yaw = QUARTER
	rig.view.pitch = math.pi / 6
	local samples: number = rig.samples
	local facing: number = rig.Predict.state().facing
	rig.frames(1, rig.delta / 3)

	local _, turned: vector = rig.Predict.eye()
	local level: number = math.cos(math.pi / 6)
	if math.abs(turned.x + level) > CLOSE or math.abs(turned.z) > CLOSE or math.abs(turned.y - 0.5) > CLOSE then
		return false, `In the frame the look turned, the eye published {turned}, not a quarter turn looking up 30°`
	elseif rig.samples ~= samples then
		return false, "The frame that turned the look ran a tick, so the turn waited for one"
	elseif rig.Predict.state().facing ~= facing then
		return false, "The drawn body's facing turned with the frame's look, not with its ticks"
	elseif rig.looks ~= 3 then
		return false, `Three frames read the game's look {rig.looks} times, not once each`
	end

	return true, nil
end
