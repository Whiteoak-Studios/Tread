--[[
    The reliable slot table entry and death message, to and from the shapes
    Volt's Slots and Death send them in
--]]

--!strict
local Constants = require(script.Parent.Parent.Constants)
local Record = require(script.Parent.Record)

local PUSH_STEPS: number = Constants.PUSH_STEPS

-- A rig mode, as Tread's schema names them
export type Rig = "A" | "B"

-- A slot table entry as Volt's Slots sends it, the shape Tread's schema gives SlotEntry
export type Entry = {
	slot: number, -- The slot and generation
	taken: { rig: Rig, player: Instance? }?, -- Nil for a freed slot
}

local Reliable = {}

--[[
    Writes a slot's entry into into: its slot and generation, and for a
    taken slot its rig mode and, for a live player's, the Player. A rig of
    nil writes the slot freed
--]]

function Reliable.write(into: Entry, slot: number, generation: number, rig: Rig?, player: Instance?)
	into.slot = Record.id(slot, generation)

	if not rig then
		into.taken = nil

		return
	end

	local taken: { rig: Rig, player: Instance? }? = into.taken
	if taken then
		taken.rig = rig
		taken.player = player
	else
		into.taken = { rig = rig, player = player }
	end
end

--[[
    The slot, generation, rig mode and player an entry names, the rig nil
    for a freed slot
--]]

function Reliable.read(entry: Entry): (number, number, Rig?, Instance?)
	local slot: number, generation: number = Record.split(entry.slot)
	local taken: { rig: Rig, player: Instance? }? = entry.taken

	if not taken then
		return slot, generation, nil, nil
	end

	return slot, generation, taken.rig, taken.player
end

--[[
    The death message's five values for Volt's Death: the dying character's
    and its body's slots and generations, and the attack's direction for
    the ragdoll's push, a unit vector, or zero for no push
--]]

function Reliable.writeDeath(
	slot: number,
	generation: number,
	bodySlot: number,
	bodyGeneration: number,
	push: vector
): (number, number, number, number, number)
	local x: number = math.clamp(math.round(push.x * PUSH_STEPS), -PUSH_STEPS, PUSH_STEPS)
	local y: number = math.clamp(math.round(push.y * PUSH_STEPS), -PUSH_STEPS, PUSH_STEPS)
	local z: number = math.clamp(math.round(push.z * PUSH_STEPS), -PUSH_STEPS, PUSH_STEPS)

	return Record.id(slot, generation), Record.id(bodySlot, bodyGeneration), x, y, z
end

--[[
    The dying character's slot and generation, its body's, and the push's
    direction a death message names, zero for no push
--]]

function Reliable.readDeath(
	character: number,
	body: number,
	pushX: number,
	pushY: number,
	pushZ: number
): (number, number, number, number, vector)
	local slot: number, generation: number = Record.split(character)
	local bodySlot: number, bodyGeneration: number = Record.split(body)
	local push: vector = vector.create(pushX / PUSH_STEPS, pushY / PUSH_STEPS, pushZ / PUSH_STEPS)

	return slot, generation, bodySlot, bodyGeneration, push
end

return Reliable
