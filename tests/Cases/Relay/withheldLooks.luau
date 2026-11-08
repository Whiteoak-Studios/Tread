--[[
    A withheld character's look and held item ride the withheld block when
    it joins it and on each change, until the watchers acknowledge the copy
    it rode beside, never on the target's word alone, and a run that sent
    the target nothing sends it an empty block for them to ride beside
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local CULLED: vector = vector.create(20, 0, 0)
local LOOK: { [string]: any } = { head = 7, torso = 8 }
local CHANGED: { [string]: any } = { head = 9 }
local HELD: { [string]: any } = { item = 11 }
local EMPTY: number = 8 -- A block's header alone

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local slot: number = harness:spawn("Player", CULLED)
	Harness.Relay.setLook(slot, LOOK)
	harness.states[slot].held = table.clone(HELD)
	harness:hide(target, slot, true)
	harness:watch(moderator, target)

	-- It joins the withheld block with both parts, beside an empty block, since the target is sent nothing else
	moderator.lose = 1
	harness:run()

	local _, looks: { any } = Harness.withheld(moderator)
	local entry: any = Harness.find(looks, slot)
	if not entry or entry.look ~= harness:pack("slot", LOOK) or entry.held ~= harness:pack("held", HELD) then
		return false, "The withheld block did not carry the character's look and held item when it joined"
	elseif #target.seen.sizes ~= 1 or target.seen.sizes[1] ~= EMPTY then
		return false, `The target was sent {#target.seen.sizes} blocks, not one empty block for the look to ride beside`
	elseif moderator.seen.withheld[1].sequence ~= target.seen.sequences[1] then
		return false, "The withheld block did not carry the sequence of the empty block beside it"
	end

	-- The target acknowledged that copy and the moderator lost it, so the look entry comes again
	harness:run()
	_, looks = Harness.withheld(moderator)
	if Harness.count(looks, slot) ~= 1 then
		return false, "The look entry stopped once the target alone had acknowledged its copy"
	end

	harness:run()
	_, looks = Harness.withheld(moderator)
	if Harness.count(looks, slot) ~= 0 then
		return false, "The look entry rode on after the moderator acknowledged its copy"
	elseif #target.seen.sizes ~= 0 then
		return false, "The target was sent an empty block with no look entry pending"
	elseif #moderator.seen.withheld ~= 1 then
		return false, "The withheld record stopped once the look entry was acknowledged"
	end

	-- A change rides on its own, the part that changed alone
	Harness.Relay.setLook(slot, CHANGED)
	harness:run()

	_, looks = Harness.withheld(moderator)
	entry = Harness.find(looks, slot)
	if not entry or entry.look ~= harness:pack("slot", CHANGED) or entry.held ~= nil then
		return false, "A look change did not ride the withheld block with the new look alone"
	end

	return true, nil
end
