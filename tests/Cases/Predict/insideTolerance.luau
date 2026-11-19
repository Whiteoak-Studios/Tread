--[[
    A server's state inside the ground tolerance, 1 and then 2 quanta off,
    raises no correction: the body and every prediction after the server's
    command shift by the difference, so the next state that agrees shifts
    nothing more
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local QUANTUM: number = 1 / 512

return function (): (boolean, string | nil)
	for _, quanta: number in { 1, 2 } do
		local rig: any = Harness.new()
		local off: vector = vector.create(quanta * QUANTUM, 0, 0)
		rig.spawn()
		rig.frames(4)

		local second: any = rig.twin(2)
		local third: any = rig.twin(3)
		second.position += off
		third.position += off

		rig.Predict.receive(rig.owner(second, 2))
		if #rig.corrections ~= 0 then
			return false, `A state {quanta} quanta off raised a correction of {rig.corrections[1].size}`
		end

		-- The server's state for command 3 agrees with the shifted prediction, so nothing moves again
		rig.Predict.receive(rig.owner(third, 2))

		-- No time is owed, so the body draws at the tick before the newest, the state after command 3
		local drawn: vector = rig.Predict.state().position
		if drawn ~= third.position then
			return false, `{quanta} quanta off, the body drew at {drawn}, not the shifted {third.position}`
		elseif #rig.corrections ~= 0 then
			return false, `{quanta} quanta off, the agreeing state raised a correction`
		end
	end

	return true, nil
end
