--[[
    The held item the relay gives the local player's own slot reaches the
    owner's prediction, which steps its body holding it, and the slot freed
    leaves the next body holding nothing
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local GENERATION: number = 1
local NEXT_GENERATION: number = 2
local TICK: number = 100
local RELAY_TICK: number = 30
local ITEM: number = 3

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local Predict: any = rig.Predict

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(vector.zero, 0, TICK))
	rig.relay({ tick = RELAY_TICK, looks = { { slot = OWN, generation = GENERATION, held = { item = ITEM } } } })

	-- 1) The own slot's held item reaches the body prediction steps
	local body: any = Predict.state()
	if body == nil or body.held.item ~= ITEM then
		return false, `The owner's predicted body held {body and body.held.item}, not the relay's item {ITEM}`
	end

	-- 2) The slot freed ends the body, and the next one holds nothing
	rig.slots({ { slot = OWN, generation = GENERATION } })
	rig.own(OWN, NEXT_GENERATION)
	rig.owner(rig.body(vector.zero, 0, TICK + 1))

	local later: any = Predict.state()
	if later == nil then
		return false, "The new body never started"
	elseif later.held.item ~= nil then
		return false, `The new body still held the freed slot's item {later.held.item}`
	end

	return true, nil
end
