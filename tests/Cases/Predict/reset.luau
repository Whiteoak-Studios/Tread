--[[
    A reset ends the body: no state and no Move until the next OwnerState,
    which starts a new body as the first did, its commands numbered past
    that state's, while the correction callbacks stay connected
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local FRAMES: number = 4
local COMMAND: number = 900 -- The new body's first OwnerState's command, far past the old body's
local TICK: number = 400

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	local Predict: any = rig.Predict

	rig.spawn()
	rig.frames(FRAMES)

	local moves: number = #rig.moves
	if moves == 0 or Predict.state() == nil then
		return false, "The first body sent no Move or had no state"
	end

	Predict.reset()

	if Predict.state() ~= nil then
		return false, "A reset body still had a state"
	end

	local closed: boolean = pcall(Predict.eye)
	if closed then
		return false, "A reset body still gave an eye"
	end

	rig.frames(FRAMES)
	if #rig.moves ~= moves then
		return false, `A reset body sent {#rig.moves - moves} Moves before any OwnerState`
	end

	rig.spawn(COMMAND, TICK)

	local state: any = Predict.state()
	if state == nil or state.command ~= COMMAND then
		return false, `The OwnerState after a reset started no body at command {COMMAND}`
	end

	rig.frames(1)

	local move: any = rig.moves[#rig.moves]
	if #rig.moves ~= moves + 1 or move.command ~= COMMAND + 1 then
		return false, `The new body's first Move carried command {move and move.command}, not {COMMAND + 1}`
	elseif #move.numbers ~= 1 then
		return false, `The new body's first Move repeated {#move.numbers - 1} commands of the old body`
	end

	-- A replay on the new body still reaches the callback connected before the reset
	rig.view.yaw = 0
	local corrections: number = #rig.corrections
	local far: any = rig.twin(COMMAND + 1)
	far.position += vector.create(5, 0, 0)
	far.tick = TICK + 1
	Predict.receive(rig.owner(far, 1))

	if #rig.corrections ~= corrections + 1 then
		return false, "A replay after the reset reached no correction callback"
	end

	return true, nil
end
