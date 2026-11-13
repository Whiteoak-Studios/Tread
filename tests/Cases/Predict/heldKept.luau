--[[
    The owner's held item, which OwnerState never carries, is kept through
    a replay from the server's state, so each aiming tick replayed steps as
    the server's step with that item does, and a reset leaves the next body
    holding nothing
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local ITEM: number = 1 -- The item whose aim the rules slow
local AIM_SPEED: number = 2 -- Studs/s the rules cap an aim with it at
local FRAMES: number = 4
local SERVER_RAN: number = 2 -- The command the server's state is after
local SHIFT: vector = vector.create(1, 0, 0) -- Past every tolerance, so the server's state replays
local CLOSE: number = 1e-9

-- The game's rules: an aim while holding the item caps the speed, and nothing else does
local function rules(step: any, _: any): number
	if step.held.item == ITEM and step.command.aim then
		return AIM_SPEED
	end

	return math.huge
end

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	local Predict: any = rig.Predict
	rig.world.rules = rules
	rig.twinWorld.rules = rules

	rig.input = function (command: any, _: number)
		command.forward = 1
		command.aim = true
		command.fields.slot = 0
		command.fields.shots = {}
	end

	rig.spawn()
	Predict.hold({ item = ITEM })
	rig.frames(FRAMES)

	-- 1) The server's state after its second command, holding the item, shifted past the tolerance
	local server: any = rig.twin(0)
	server.held = { item = ITEM }
	rig.step(server, 1, SERVER_RAN)
	server.position += SHIFT

	local replayed: any = rig.copy(server)
	replayed.held = { item = ITEM }
	rig.step(replayed, SERVER_RAN + 1, FRAMES)

	Predict.receive(rig.owner(server, 1))
	if #rig.corrections ~= 1 then
		return false, `The shifted server state raised {#rig.corrections} corrections, not one replay`
	end

	-- 2) The replay stepped every later aiming tick with the item, as the server's step with it does
	local drawn: any = Predict.state()
	if drawn.held.item ~= ITEM then
		return false, "The replay dropped the held item the owner's body holds"
	elseif vector.magnitude(drawn.velocity - replayed.velocity) > CLOSE then
		return false, `The replay moved at {drawn.velocity}, not the server's step with the item's {replayed.velocity}`
	elseif math.abs(vector.magnitude(replayed.velocity) - AIM_SPEED) > CLOSE then
		return false,
			`The server's step with the item moved at {vector.magnitude(replayed.velocity)}, not its aim speed`
	end

	-- 3) A reset and a new body with no item hold nothing
	Predict.reset()
	rig.spawn()
	if next(Predict.state().held) ~= nil then
		return false, "The new body after a reset still held the old one's item"
	end

	return true, nil
end
