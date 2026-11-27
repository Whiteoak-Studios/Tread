--[[
    A command with no prediction carries a check of 0: one whose step threw,
    each one a replay that threw never reached, and one whose state OwnerState
    can't hold; a client with no body sends no Move, and so no check at all
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local IDLE: number = 3 -- Frames run with no body
local DEPTH: number = 2
local PAST: number = 99 -- A sinceJump the fixture game's 4-bit field can't hold
local OFF: vector = vector.create(0, 0, 1) -- How far the server's state is off the prediction, past the tolerance

return function (): (boolean, string | nil)
	local wild: boolean = false

	-- The game's rules, which while wild set a field past what its declaration holds
	local function rules(step: any, _: any): number
		step.block.sinceJump = wild and PAST or 0

		return math.huge
	end

	local rig: any = Harness.new({ rules = rules })

	-- With no body the client sends nothing
	rig.frames(IDLE)
	if #rig.moves ~= 0 then
		return false, `With no body the client sent {#rig.moves} Moves`
	end

	-- Commands 1 and 2 predicted, then 3 whose step throws, then 4 predicted from where the body held
	rig.spawn()
	rig.frames(2)
	rig.fail = true
	rig.frames(1)
	rig.fail = false
	rig.frames(1)

	for number: number = 1, 2 do
		if rig.checks[number] == 0 or rig.checks[number] ~= rig.hash(rig.twin(number), DEPTH) then
			return false, `Predicted command {number} carried check {rig.checks[number]}, not the server's hash`
		end
	end

	local move: any = rig.moves[#rig.moves]
	if move.numbers[2] ~= 3 or move.checks[2] ~= 0 then
		return false, `Command 3, whose step threw, went with check {move.checks[2]}, not 0`
	elseif rig.checks[4] == 0 then
		return false, "Command 4, predicted from where the body held, went with check 0"
	end

	-- Command 5's state holds a field its declaration doesn't, so OwnerState can't write it, though the step ran
	wild = true
	rig.frames(1)
	wild = false
	rig.frames(1)

	if rig.checks[5] ~= 0 then
		return false, `A state OwnerState can't hold went with check {rig.checks[5]}, not 0`
	elseif rig.checks[6] == 0 then
		return false, "The command after the unwritable state went with check 0"
	end

	-- A correction for command 2 whose replay throws at command 3, so 3 to 6 hold no prediction
	local server: any = rig.twin(2)
	server.position += OFF
	rig.fail = true
	rig.Predict.receive(rig.owner(server, DEPTH))
	rig.fail = false
	rig.frames(1)

	move = rig.moves[#rig.moves]
	if move.command ~= 7 or move.checks[2] ~= 0 or move.checks[3] ~= 0 then
		return false, `After the replay threw, commands 6 and 5 went with checks {move.checks[2]} and {move.checks[3]}`
	elseif move.checks[1] == 0 then
		return false, "The command made after the replay threw went with check 0"
	end

	-- Once the body ends, no Move goes until the next one starts
	local sent: number = #rig.moves
	rig.Predict.reset()
	rig.frames(IDLE)
	if #rig.moves ~= sent then
		return false, `With its body ended the client sent {#rig.moves - sent} Moves`
	end

	return true, nil
end
