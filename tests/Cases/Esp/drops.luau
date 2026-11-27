--[[
    A block that hides a slot, the slot table freeing it and the table giving
    it a new life each drop its box, while a hide naming another life, a late
    record of a freed slot and one of an older life draw nothing back
--]]

--!strict
local Rig = require("../../Fixtures/Esp/Rig")

local HIDDEN: number = 3
local FREED: number = 5
local RENEWED: number = 6
local KEPT: number = 7
local TICK: number = 50
local FRAMES: number = 3

local SLOTS: { number } = { HIDDEN, FREED, RENEWED, KEPT }

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local switch: (on: boolean) -> () = rig.startEsp()
	switch(true)

	local at: vector = vector.create(10, 0, 10)

	local function record(slot: number, generation: number): { [string]: any }
		return { slot = slot, generation = generation, position = at, word = rig.word({}) }
	end

	local function reveal(slot: number, generation: number): { [string]: any }
		return { slot = slot, generation = generation, kind = "Npc" }
	end

	-- Whether a slot's box and label both show
	local function visible(slot: number): boolean
		local _, box: any, label: any = rig.slot(slot)

		return box ~= nil and box.Visible and label.Parent.Enabled
	end

	local entries: { any } = {}
	local reveals: { any } = {}
	local records: { any } = {}
	for _, slot: number in SLOTS do
		table.insert(entries, { slot = slot, generation = 1, rig = "A" })
		table.insert(reveals, reveal(slot, 1))
		table.insert(records, record(slot, 1))
	end

	rig.slots(entries)
	rig.relay({ tick = TICK, reveals = reveals, records = records })
	rig.frames(FRAMES)

	for _, slot: number in SLOTS do
		if not visible(slot) then
			return false, `Slot {slot}'s box didn't show at its first record`
		end
	end

	-- 1) A hide of the record's life drops its box, and one naming another life changes nothing
	rig.relay({ tick = TICK + 1, hides = { { slot = HIDDEN, generation = 1 }, { slot = KEPT, generation = 2 } } })
	rig.frames(FRAMES)

	if visible(HIDDEN) then
		return false, "A block hid slot 3 and its box stayed"
	elseif not visible(KEPT) then
		return false, "A hide naming slot 7's next life dropped the box of its current one"
	end

	-- 2) The slot table freeing a slot drops its box, and a late record of the freed life draws none
	rig.slots({ { slot = FREED, generation = 1 } })
	rig.frames(FRAMES)

	if visible(FREED) then
		return false, "The slot table freed slot 5 and its box stayed"
	end

	rig.relay({ tick = TICK + 2, records = { record(FREED, 1) } })
	rig.frames(FRAMES)

	if visible(FREED) then
		return false, "A late record of freed slot 5 drew its box again"
	end

	-- 3) A new life drops the old life's box, whose records then draw none, and its own record draws it
	rig.slots({ { slot = RENEWED, generation = 2, rig = "A" } })
	rig.frames(FRAMES)

	if visible(RENEWED) then
		return false, "The slot table gave slot 6 a new life and the old life's box stayed"
	end

	rig.relay({ tick = TICK + 3, records = { record(RENEWED, 1) } })
	rig.frames(FRAMES)

	if visible(RENEWED) then
		return false, "A record of slot 6's old life drew its box after the new life began"
	end

	rig.relay({ tick = TICK + 4, reveals = { reveal(RENEWED, 2) }, records = { record(RENEWED, 2) } })
	rig.relay({ tick = TICK + 4, reveals = { reveal(HIDDEN, 1) }, records = { record(HIDDEN, 1) } })
	rig.frames(FRAMES)

	if not visible(RENEWED) then
		return false, "Slot 6's new life's record drew no box"
	elseif not visible(HIDDEN) then
		return false, "Slot 3, revealed again after its hide, drew no box"
	end

	switch(false)

	return true, nil
end
