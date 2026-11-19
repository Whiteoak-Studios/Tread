--[[
    A keyframe carries its view's own character after the platforms, its id,
    look and held item, long after the own look entry was acknowledged; a
    spectating moderator's is its target's, and a view with none carries none
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local KEYFRAME: string = "src/Codec/Keyframe.luau"
local RECORD: string = "src/Codec/Record.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local LOOK: { [string]: any } = { head = 4, torso = 5 }
local MODERATOR_LOOK: { [string]: any } = { shirt = 6 }
local HELD: { [string]: any } = { item = 12 }
local RUNS: number = 6 -- Enough for every look entry to be carried and acknowledged

-- Why a keyframe's own character is not the slot given wearing the look and held item given, or nil when it is
local function wrong(Record: any, own: any, slot: number, generation: number, look: string, held: string): string?
	if own == nil then
		return "it carries no own character"
	elseif own.id ~= Record.id(slot, generation) then
		return `its own character's id is {own.id}, not slot {slot}'s {Record.id(slot, generation)}`
	elseif buffer.tostring(own.look) ~= look then
		return "its own look is not the slot's"
	elseif buffer.tostring(own.held) ~= held then
		return "its own held item is not the slot's"
	end

	return nil
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Keyframe: any = Environment.load(KEYFRAME)
	local Record: any = Environment.load(RECORD)

	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	local stranger: any = harness:viewer("Stranger")
	moderator.viewer.position = AWAY
	stranger.viewer.position = AWAY

	-- The target and the moderator each own a character, dressed apart
	local targetSlot: number = harness:spawn("Player", vector.zero)
	local moderatorSlot: number = harness:spawn("Player", AWAY)
	target.viewer.slot = targetSlot
	moderator.viewer.slot = moderatorSlot

	Harness.Relay.setLook(targetSlot, LOOK)
	Harness.Relay.setLook(moderatorSlot, MODERATOR_LOOK)
	harness.states[targetSlot].held = table.clone(HELD)
	harness:spawn("Player", vector.create(-20, 0, 0))
	harness:runs(RUNS)

	local look: string = harness:pack("slot", LOOK)
	local held: string = harness:pack("held", HELD)
	local generation: number = Harness.Slots.get(targetSlot)

	-- The own look entry was acknowledged runs ago, and the keyframe still carries it
	if target.newest == 0 or #target.sent ~= 0 then
		return false, "The target's client read nothing or holds acknowledgments back"
	end

	local own: any = Keyframe.read(Harness.Relay.keyframe(target.viewer.key))
	local why: string? = wrong(Record, own.own, targetSlot, generation, look, held)
	if why then
		return false, `The target's keyframe: {why}`
	end

	for _, character: any in own.characters do
		local record: any = Record.new()
		Record.read(character.record, 0, record, harness.limits)
		if record.slot == targetSlot then
			return false, "The target's keyframe lists its own character among those it is sent"
		end
	end

	-- A moderator watching the target carries the target's own character, not its own
	harness:watch(moderator, target)
	harness:runs(RUNS)

	local watched: any = Keyframe.read(Harness.Relay.keyframe(moderator.viewer.key))
	why = wrong(Record, watched.own, targetSlot, generation, look, held)
	if why then
		return false, `The spectating moderator's keyframe: {why}`
	end

	-- Back on its own view, the moderator carries its own character, which holds nothing
	harness:watch(moderator, nil)
	harness:runs(RUNS)

	local back: any = Keyframe.read(Harness.Relay.keyframe(moderator.viewer.key))
	local moderatorGeneration: number = Harness.Slots.get(moderatorSlot)
	why = wrong(Record, back.own, moderatorSlot, moderatorGeneration, harness:pack("slot", MODERATOR_LOOK), "")
	if why then
		return false, `The moderator's own keyframe: {why}`
	end

	-- A view with no character of its own carries none
	if Keyframe.read(Harness.Relay.keyframe(stranger.viewer.key)).own ~= nil then
		return false, "A viewer with no character got a keyframe with an own character"
	end

	return true, nil
end
