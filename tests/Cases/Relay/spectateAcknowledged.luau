--[[
    A watched target's reveals, looks and hides ride its blocks until the
    target and every watcher have acknowledged one that carried them, so a
    copy a moderator lost comes again though the target acknowledged it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local NEAR: vector = vector.create(30, 0, 0)
local AWAY: vector = vector.create(1500, 0, 0) -- Past the target's relevancy
local LOOK: { [string]: any } = { head = 4 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local slot: number = harness:spawn("Player", NEAR)
	harness:run()

	-- The start's reveal reaches the target, the moderator loses its copy, and it rides again for the moderator
	harness:watch(moderator, target)
	Harness.Relay.revealAll(target.viewer.key)
	moderator.lose = 1
	harness:run()

	if Harness.count(target.seen.reveals, slot) ~= 1 or moderator.seen.lost ~= 1 then
		return false, "The start's reveal did not reach the target while the moderator lost its copy"
	end

	harness:run()
	if Harness.count(moderator.seen.reveals, slot) ~= 1 or moderator.drawn[slot] == nil then
		return false, "The reveal the moderator lost did not come again once the target had acknowledged it"
	end

	harness:run()
	if Harness.count(target.seen.reveals, slot) + Harness.count(moderator.seen.reveals, slot) ~= 0 then
		return false, "The reveal rode on after the target and the moderator had both acknowledged it"
	end

	-- A look change the moderator loses rides on for it alone to read, then stops
	Harness.Relay.setLook(slot, LOOK)
	moderator.lose = 1
	harness:run()

	harness:run()
	local look: any = Harness.find(moderator.seen.looks, slot)
	if not look or look.look ~= harness:pack("slot", LOOK) then
		return false, "The look entry the moderator lost did not come again"
	end

	harness:run()
	if Harness.count(target.seen.looks, slot) + Harness.count(moderator.seen.looks, slot) ~= 0 then
		return false, "The look entry rode on after both acknowledged it"
	end

	-- The target's acknowledgment alone never clears a hide while the moderator's is late
	moderator.lag = 2
	harness.states[slot].position = AWAY + AWAY
	harness:run()

	if Harness.count(target.seen.hides, slot) ~= 1 then
		return false, "Leaving the target's range sent no hide"
	end

	harness:runs(2)
	if Harness.count(target.seen.hides, slot) ~= 1 then
		return false, "The hide stopped riding before the late moderator acknowledged it"
	end

	harness:runs(2)
	if Harness.count(target.seen.hides, slot) ~= 0 or moderator.drawn[slot] ~= nil then
		return false, "The hide rode on, or never reached the moderator, once both had acknowledged it"
	end

	return true, nil
end
