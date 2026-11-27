--[[
    A client more than the resync ahead of its target lead snaps backward:
    it issues no command and samples nothing until the server reaches the
    target, its Moves carrying acknowledgments alone, then goes on one past
    its newest, never reusing a number
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(4)

	-- A queue of 2 behind command 2, with the client at 4, shows a round trip of nothing
	rig.Predict.receive(rig.owner(rig.twin(2), 2))
	rig.frames(8)

	-- A queue at the ahead limit behind command 3, with the client at 12, puts the lead at 9: 7 past the band's middle
	rig.Predict.receive(rig.owner(rig.twin(3), 5))

	-- Another from before the hold took hold changes nothing
	rig.Predict.receive(rig.owner(rig.twin(5), 5))

	local moves: number = #rig.moves
	rig.frames(7)
	if rig.samples ~= 12 then
		return false, `The 7 held ticks sampled {rig.samples - 12} times, not none`
	elseif #rig.moves ~= moves + 7 then
		return false, `The 7 held ticks sent {#rig.moves - moves} Moves, not 7`
	end

	for index: number = moves + 1, #rig.moves do
		local move: any = rig.moves[index]
		if #move.numbers ~= 0 or move.command ~= 0 or move.acknowledged ~= 7 then
			return false, `A held tick's Move carried {#move.numbers} commands, or no acknowledgments`
		end
	end

	rig.frames(1)
	local move: any = rig.moves[#rig.moves]
	if rig.samples ~= 13 or move.command ~= 13 or #move.numbers ~= 3 then
		local got: string = `{rig.samples} samples and a Move of {#move.numbers} commands, newest {move.command}`
		return false, `After the hold the clock gave {got}, not 13 samples and 13, 12 and 11`
	end

	return true, nil
end
