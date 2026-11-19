--[[
    A game hook that throws during a replay ends it, and the body snaps to
    the server's state with no visual error offset; the commands it never
    replayed hold no prediction, so the server's next state replays again
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(4)

	local server: any = rig.twin(2)
	server.position += vector.create(0, 0, 1)
	rig.fail = true
	rig.Predict.receive(rig.owner(server, 2))
	rig.fail = false

	local drawn: vector = rig.Predict.state().position
	if drawn ~= server.position then
		return false, `After the replay threw the body drew at {drawn}, not the server's {server.position}`
	elseif #rig.corrections ~= 1 then
		return false, `The replay that threw raised {#rig.corrections} corrections, not 1`
	end

	-- Command 4 holds no prediction now, so the server's state for it replays and counts as flagged
	local fourth: any = rig.copy(server)
	rig.step(fourth, 3, 4)
	rig.Predict.receive(rig.owner(fourth, 0))
	if #rig.corrections ~= 2 or rig.corrections[2].flagged ~= true then
		return false, "The server's state for a command the replay never reached did not replay as flagged"
	end

	return true, nil
end
