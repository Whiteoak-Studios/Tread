--[[
    The client steps its command at the numbers the wire carries, not the
    sample's own: a move of 0.3 and 0.2 and a yaw off the u16 steps predict
    exactly the path the server runs from the same wires
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new({ tolerances = { Ground = 0, Air = 0 } })
	rig.input = function (command: any, _: number)
		command.forward = 0.3
		command.right = 0.2
		command.yaw = 0.1234
		command.pitch = 0.3
		command.fields.slot = 5
		command.fields.shots = {}
	end

	rig.spawn()
	rig.frames(4)

	for _, through: number in { 2, 4 } do
		rig.Predict.receive(rig.owner(rig.twin(through), 0))
	end

	if #rig.corrections ~= 0 then
		local correction: any = rig.corrections[1]
		return false, `The server's path from the same wires raised a correction of {correction.size} studs`
	end

	return true, nil
end
