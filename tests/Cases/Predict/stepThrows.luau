--[[
    A game hook that throws in a tick's prediction leaves the body where it
    was and still sends the command, which the server runs, so its state
    for that command replays, flagged, since nothing predicted it
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(2)

	rig.fail = true
	rig.frames(1)
	rig.fail = false

	local second: any = rig.twin(2)
	local move: any = rig.moves[#rig.moves]
	if move.command ~= 3 then
		return false, `The tick whose step threw sent {move.command} as its newest command, not 3`
	elseif rig.Predict.state().position ~= second.position then
		return false, `The tick whose step threw moved the body to {rig.Predict.state().position}`
	end

	rig.Predict.receive(rig.owner(rig.twin(3), 0))
	if #rig.corrections ~= 1 or rig.corrections[1].flagged ~= true then
		return false, "The server's state for the command whose step threw did not replay as flagged"
	end

	return true, nil
end
