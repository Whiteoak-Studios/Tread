--[[
    No block passes 896 B: a tick's records past the 55 one block holds go
    in the next, each record once, an acknowledgment of either block clears
    what it carried, and what the tick's budget can't fit waits for the next
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local BLOCK: number = 896
local PER_BLOCK: number = 55
local CROWD: number = 60
local STRIDE: number = 0.25
local SOFT: number = 64 * 1000 -- The example's soft budget, bytes a second
local ONE_BLOCK: number = 900 -- Room for one block of 55 records and its framing, not for two

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)

	-- Whole records, since the blocks this case fills are counted in 16 B records
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay.changes = false
	end)
	local client: any = harness:viewer("Viewer")

	local slots: { number } = {}
	for index: number = 1, CROWD do
		table.insert(slots, harness:spawn("Player", vector.create(index, 0, 10)))
	end

	local function move()
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(0, 0, STRIDE)
		end
	end

	harness:run()
	if #client.seen.reveals ~= CROWD or #client.seen.blocks < 2 then
		return false, `The first tick revealed {#client.seen.reveals} of {CROWD} in {#client.seen.blocks} blocks`
	end

	-- Both reveal blocks were acknowledged, the second through the newest and the first through the mask
	move()
	harness:run()

	local seen: any = client.seen
	if #seen.reveals ~= 0 then
		return false, `{#seen.reveals} reveals rode on after both their blocks were acknowledged`
	elseif #seen.records ~= CROWD or #seen.blocks ~= 2 then
		return false, `{CROWD} moving characters gave {#seen.records} records in {#seen.blocks} blocks`
	elseif #seen.blocks[1].records ~= PER_BLOCK then
		return false, `The first block held {#seen.blocks[1].records} records, not the {PER_BLOCK} that fill it`
	end

	for _, size: number in seen.sizes do
		if size > BLOCK then
			return false, `A block of {size} B passed the {BLOCK} B bound`
		end
	end

	for _, slot: number in slots do
		if Harness.count(seen.records, slot) ~= 1 then
			return false, `Slot {slot} had {Harness.count(seen.records, slot)} records in one tick`
		end
	end

	-- With room for one block a tick, the five left over go the next tick, ahead of the rest
	harness.traffic = SOFT - ONE_BLOCK
	move()
	harness:run()

	local first: any = client.seen
	if #first.blocks ~= 1 or #first.records ~= PER_BLOCK then
		return false, `With room for one block the tick sent {#first.records} records in {#first.blocks} blocks`
	end

	move()
	harness:run()

	for _, slot: number in slots do
		if Harness.count(first.records, slot) + Harness.count(client.seen.records, slot) == 0 then
			return false, `Slot {slot}, cut from the full tick, was not sent on the next`
		end
	end

	return true, nil
end
