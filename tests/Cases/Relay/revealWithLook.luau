--[[
    A reveal shares its block with its look entry, carrying both the look
    and the held item, and with its record, however many reveals a tick
    spreads over its blocks
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local CROWD: number = 40 -- More reveals than one block holds
local SPACING: number = 3

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")

	local looks: { [number]: string } = {}
	local helds: { [number]: string } = {}

	for index: number = 1, CROWD do
		local slot: number = harness:spawn("Player", vector.create(index * SPACING, 0, 0))
		local look: { [string]: any } = { head = index, torso = 100 + index, face = 7 }
		local held: { [string]: any } = { item = index }

		Harness.Relay.setLook(slot, look)
		harness.states[slot].held = held
		looks[slot] = harness:pack("slot", look)
		helds[slot] = harness:pack("held", held)
	end

	harness:run()

	local seen: any = client.seen
	if #seen.reveals ~= CROWD then
		return false, `The tick revealed {#seen.reveals} of the {CROWD} characters in range`
	elseif #seen.blocks < 2 then
		return false, `{CROWD} reveals with their looks fit in {#seen.blocks} block, so none was spread`
	end

	for index: number, block: any in seen.blocks do
		for _, slot: number in block.reveals do
			if not table.find(block.looks, slot) or not table.find(block.records, slot) then
				return false, `Block {index} revealed slot {slot} without its look entry and record beside it`
			end
		end
	end

	for slot: number, look: string in looks do
		local entry: any = Harness.find(seen.looks, slot)
		if not entry or entry.look ~= look or entry.held ~= helds[slot] then
			return false, `Slot {slot}'s reveal carried other than its look and its held item`
		end
	end

	return true, nil
end
