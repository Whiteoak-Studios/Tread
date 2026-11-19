--[[
    After a correction replays, the next Move's spares carry the checks of
    the replayed predictions, which are the server's own hashes along its
    path, and so does every command made from then on
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local MADE: number = 5 -- Commands made before the correction
local CORRECTED: number = 2 -- The command whose state the server corrects
local LAST: number = 20 -- The newest command the case runs to
local DEPTH: number = 2
local OFF: vector = vector.create(0.25, 0, 1) -- How far the server's state is off the prediction, past the tolerance

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(MADE)

	local sent: { [number]: number } = table.clone(rig.checks)

	local server: any = rig.twin(CORRECTED)
	server.position += OFF
	rig.Predict.receive(rig.owner(server, DEPTH))
	if #rig.corrections ~= 1 then
		return false, `A state a stud off raised {#rig.corrections} corrections, not 1`
	end

	-- The server's own path on from its corrected state, and its hash after each command
	local path: any = rig.copy(server)
	local hashes: { [number]: number } = {}
	for number: number = CORRECTED + 1, MADE do
		rig.step(path, number, number)
		hashes[number] = rig.hash(rig.copy(path), DEPTH)

		if hashes[number] == sent[number] then
			return false, `Command {number}'s check before the replay already matched the server's path`
		end
	end

	for number: number = MADE + 1, LAST do
		rig.frames(1)
		rig.step(path, number, number)
		hashes[number] = rig.hash(rig.copy(path), DEPTH)

		-- The newest command and the spares before it, the first Move's spares the replayed ones
		local move: any = rig.moves[#rig.moves]
		for index: number, carried: number in move.numbers do
			if move.checks[index] ~= hashes[carried] then
				local check: number = move.checks[index]
				return false, `Command {carried} went in Move {number} with {check}, not the server's {hashes[carried]}`
			end
		end
	end

	return true, nil
end
