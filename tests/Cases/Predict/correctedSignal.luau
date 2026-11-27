--[[
    onCorrected's callbacks each hear every replay, one that throws stops
    neither the others nor the replay, and the closure each returns
    disconnects it, so it hears no later replay
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	local heard: number = 0

	rig.Predict.onCorrected(function (_: number, _: boolean)
		error("This correction callback throws on purpose, to show the others still run")
	end)

	local disconnect: () -> () = rig.Predict.onCorrected(function (_: number, _: boolean)
		heard += 1
	end)

	rig.spawn()
	rig.frames(4)

	local server: any = rig.twin(2)
	server.position += vector.create(0, 0, 1)
	rig.Predict.receive(rig.owner(server, 2))
	if heard ~= 1 or #rig.corrections ~= 1 then
		return false, `One replay reached {heard} and {#rig.corrections} callbacks past one that threw, not 1 and 1`
	end

	disconnect()

	local again: any = rig.copy(server)
	rig.step(again, 3, 3)
	again.position += vector.create(0, 0, 1)
	rig.Predict.receive(rig.owner(again, 2))
	if heard ~= 1 or #rig.corrections ~= 2 then
		return false, `After its disconnect a callback heard {heard - 1} more replays`
	end

	return true, nil
end
