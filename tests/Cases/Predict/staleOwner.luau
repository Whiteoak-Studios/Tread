--[[
    An OwnerState no newer than the last read, arriving late or twice,
    changes nothing, however far off the state it carries
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(4)

	local older: any = rig.twin(2)
	local newer: any = rig.twin(3)
	rig.Predict.receive(rig.owner(newer, 1))

	local drawn: vector = rig.Predict.state().position

	older.position += vector.create(5, 0, 0)
	rig.Predict.receive(rig.owner(older, 2))
	newer.position += vector.create(5, 0, 0)
	rig.Predict.receive(rig.owner(newer, 1))

	if #rig.corrections ~= 0 then
		return false, `A late or repeated OwnerState raised {#rig.corrections} corrections`
	elseif rig.Predict.state().position ~= drawn then
		return false, "A late or repeated OwnerState moved the body"
	end

	return true, nil
end
