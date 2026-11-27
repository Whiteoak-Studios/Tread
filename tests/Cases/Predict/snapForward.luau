--[[
    A client more than the resync behind its target lead snaps forward:
    it skips the numbers between, so its next command is numbered for the
    target, the Move after carries no command from before the skip, and a
    state sent before the snap took hold changes the clock no more
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(6)

	-- A queue of 1 behind command 2, with the client at 6, shows a round trip of 3 commands
	rig.Predict.receive(rig.owner(rig.twin(2), 1))
	rig.frames(1)

	-- An empty queue at the client's newest, 7, puts the lead at 0 less that trip, 3 ticks late: 5 short of the
	-- band's middle of 2, so 5 numbers are skipped
	rig.Predict.receive(rig.owner(rig.twin(7), 0))
	rig.frames(1)

	local move: any = rig.moves[#rig.moves]
	if move.command ~= 13 or #move.numbers ~= 1 then
		return false, `The Move after the snap carried {#move.numbers} commands, newest {move.command}, not 13 alone`
	elseif rig.samples ~= 8 then
		return false, `The snap changed how often the sample runs: {rig.samples} samples in 8 ticks`
	end

	-- The server's tick for command 8 comes before the snap's first command, so the clock judges nothing
	local late: any = rig.twin(7)
	late.command = 8
	late.tick = 108
	rig.Predict.receive(rig.owner(late, 0))
	rig.frames(1)

	move = rig.moves[#rig.moves]
	if move.command ~= 14 then
		return false, `A state from before the snap moved the clock again: the next command was {move.command}`
	end

	return true, nil
end
