--[[
    Past the tolerance the body resets to the server's state and replays
    every command after the server's, so its predictions are the server's
    own path from there: the next states the server sends along that path
    raise no other correction
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	-- A snap of 0 leaves no visual error offset, so the drawn body is the replayed one
	local rig: any = Harness.new({ snap = 0 })
	rig.spawn()
	rig.frames(5)

	-- The server's body ran command 2 a stud further back and a little to the side
	local server: any = rig.twin(2)
	server.position += vector.create(0.25, 0, 1)
	rig.Predict.receive(rig.owner(server, 2))

	if #rig.corrections ~= 1 then
		return false, `A state a stud off raised {#rig.corrections} corrections, not 1`
	end

	-- The server's own path from its state through commands 3 to 5
	local third: any = rig.copy(server)
	rig.step(third, 3, 3)
	local fourth: any = rig.copy(third)
	rig.step(fourth, 4, 4)
	local fifth: any = rig.copy(fourth)
	rig.step(fifth, 5, 5)

	-- No time is owed, so the body draws at the tick before the newest, the replay's state after command 4
	local drawn: vector = rig.Predict.state().position
	if drawn ~= fourth.position then
		return false, `After the replay the body drew at {drawn}, not the server's path at {fourth.position}`
	end

	rig.Predict.receive(rig.owner(third, 2))
	rig.Predict.receive(rig.owner(fifth, 0))
	if #rig.corrections ~= 1 then
		return false, "A state along the server's replayed path raised another correction"
	end

	return true, nil
end
