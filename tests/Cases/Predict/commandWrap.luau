--[[
    Command numbers run across the u16 wrap: after 65534 come 65535, 0 and
    1, each Move numbers its commands down across it, and the server's
    states on either side of it reconcile, a replay from before it included
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn(65534, 100)
	rig.frames(4)

	local want: { { number } } = { { 65535 }, { 0, 65535 }, { 1, 0, 65535 }, { 2, 1, 0 } }
	for index: number, numbers: { number } in want do
		local move: any = rig.moves[index]
		for position: number, number: number in numbers do
			if move.numbers[position] ~= number then
				return false, `Move {index}'s command {position} was {move.numbers[position]}, not {number}`
			end
		end
	end

	-- The server's states for 0 and 2 agree with the prediction
	rig.Predict.receive(rig.owner(rig.twin(0), 2))
	rig.Predict.receive(rig.owner(rig.twin(2), 0))
	if #rig.corrections ~= 0 then
		return false, "A state across the wrap that agrees with the prediction raised a correction"
	end

	-- One that ran 65535 elsewhere replays 0, 1 and 2 from it, after which its own path agrees
	local other: any = Harness.new()
	other.spawn(65534, 100)
	other.frames(3)

	local server: any = other.twin(65535)
	server.position += vector.create(0, 0, 1)
	other.Predict.receive(other.owner(server, 2))

	local after: any = other.copy(server)
	other.step(after, 0, 1)
	other.Predict.receive(other.owner(after, 0))
	if #other.corrections ~= 1 then
		return false, `A replay across the wrap left {#other.corrections} corrections, not the one that started it`
	end

	return true, nil
end
