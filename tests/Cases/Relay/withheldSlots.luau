--[[
    A watched target's withheld block goes to its watchers alone and holds
    its culled players only, never an NPC or an Invisible or Parked one,
    each every tier tick at the target's aim rate, changed or not, outside
    the target's budget, and carrying the sequence of the run's last copy
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local NEAR_CULLED: vector = vector.create(20, 0, 0)
local FAR_CULLED: vector = vector.create(400, 0, 0) -- Past the near tier
local VISIBLE: vector = vector.create(0, 0, 30)
local NPC: vector = vector.create(0, 0, -30)
local INVISIBLE: vector = vector.create(-20, 0, 0)
local PARKED: vector = vector.create(10, 0, 10)
local TICKS: number = 8
local FAR_SENT: number = 6 -- The far tier's 15 Hz aim at a 20 Hz relay over those ticks, its first at once
local HARD: number = 96 * 1000 -- The example's hard budget, bytes a second
local STRIDE: vector = vector.create(0, 0, 0.5)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local near: number = harness:spawn("Player", NEAR_CULLED)
	local far: number = harness:spawn("Player", FAR_CULLED)
	local visible: number = harness:spawn("Player", VISIBLE)
	local npc: number = harness:spawn("Npc", NPC)
	local invisible: number = harness:spawn("Player", INVISIBLE)
	local parked: number = harness:spawn("Player", PARKED)

	for _, slot: number in { near, far, npc, invisible, parked } do
		harness:hide(target, slot, true)
	end

	Harness.Relay.setInvisible(invisible, true)
	harness.states[parked].moveMode = "Parked"
	harness:watch(moderator, target)

	local counts: { [number]: number } = {}
	for tick: number = 1, TICKS do
		harness:run()

		if #harness.withheldSends == 0 then
			return false, `Tick {tick} sent no withheld block`
		end

		for _, keys: { any } in harness.withheldSends do
			if #keys ~= 1 or keys[1] ~= moderator.viewer.key then
				return false, `Tick {tick} sent a withheld block to {#keys} keys, not to the moderator alone`
			end
		end

		if #target.seen.withheld ~= 0 then
			return false, "The target was sent a withheld block"
		end

		local records: { any } = Harness.withheld(moderator)
		for _, record: any in records do
			counts[record.slot] = (counts[record.slot] or 0) + 1
		end

		for _, block: any in moderator.seen.withheld do
			if block.sequence ~= target.newest then
				return false,
					`Tick {tick}'s withheld block carried {block.sequence}, not the last copy's {target.newest}`
			end
		end
	end

	if counts[near] ~= TICKS then
		return false,
			`The near culled player, standing still, had {counts[near] or 0} withheld records in {TICKS} ticks`
	elseif counts[far] ~= FAR_SENT then
		return false, `The far culled player had {counts[far] or 0} withheld records, not {FAR_SENT} at its aim rate`
	end

	for _, slot: number in { visible, npc, invisible, parked } do
		if counts[slot] ~= nil then
			return false, `Slot {slot}, which is no culled player the target is not sent, was withheld`
		end
	end

	-- With no room left in the target's budget it is sent nothing, and the withheld block goes all the same
	harness.traffic = HARD
	harness.states[visible].position += STRIDE
	harness:run()

	local records: { any } = Harness.withheld(moderator)
	if #target.seen.sizes ~= 0 then
		return false, "The target was sent a block with no room left in its budget"
	elseif Harness.count(records, near) ~= 1 then
		return false, "The withheld block took room from the target's budget, and went without its near player"
	end

	-- A culled player the target comes to see leaves the withheld block the run it is revealed
	harness.traffic = 0
	harness:hide(target, near, false)
	harness:run()

	records = Harness.withheld(moderator)
	if Harness.count(target.seen.reveals, near) ~= 1 then
		return false, "The target was not revealed the player once anti-ESP stopped hiding it"
	elseif Harness.count(records, near) ~= 0 then
		return false, "A player the target is sent was still withheld"
	end

	return true, nil
end
