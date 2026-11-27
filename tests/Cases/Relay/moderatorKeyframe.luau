--[[
    A spectating moderator's keyframe holds its target's characters, its
    newest copy's sequence, and the players withheld from the target with
    their looks, bit 7 set in each kind byte, which the target's own lacks
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local KEYFRAME: string = "src/Codec/Keyframe.luau"
local RECORD: string = "src/Codec/Record.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local LOOK: { [string]: any } = { head = 7, torso = 8 }
local SEEN_LOOK: { [string]: any } = { shirt = 3 }
local HELD: { [string]: any } = { item = 11 }
local RUNS: number = 3
local HEADER_BYTES: number = 12 -- A keyframe's version, hash, tick, sequence and count, before its characters
local RECORD_BYTES: number = 16
local WITHHELD_BIT: number = 7
local PLAYER_CODE: number = 0

-- Each character's raw kind byte in a keyframe, in its order, walking its records, looks and held items
local function kindBytes(data: buffer): { number }
	local codes: { number } = {}
	local offset: number = HEADER_BYTES

	for _ = 1, buffer.readu16(data, 10) do
		table.insert(codes, buffer.readu8(data, offset))
		offset += 1 + RECORD_BYTES

		local look: number = buffer.readu8(data, offset)
		offset += 1 + look

		local held: number = buffer.readu8(data, offset)
		offset += 1 + held
	end

	return codes
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Keyframe: any = Environment.load(KEYFRAME)
	local Record: any = Environment.load(RECORD)

	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local culled: number = harness:spawn("Player", vector.create(20, 0, 0))
	local seen: number = harness:spawn("Player", vector.create(-20, 0, 0))
	harness:hide(target, culled, true)
	Harness.Relay.setLook(culled, LOOK)
	Harness.Relay.setLook(seen, SEEN_LOOK)
	harness.states[culled].held = table.clone(HELD)

	harness:watch(moderator, target)
	harness:runs(RUNS)

	local data: buffer = Harness.Relay.keyframe(moderator.viewer.key)
	local keyframe: any = Keyframe.read(data)
	local codes: { number } = kindBytes(data)

	if keyframe.sequence ~= moderator.newest then
		return false,
			`The moderator's keyframe names sequence {keyframe.sequence}, not its newest copy's {moderator.newest}`
	elseif #keyframe.characters ~= 2 then
		return false,
			`The moderator's keyframe holds {#keyframe.characters} characters, not the seen and the withheld one`
	end

	local found: { [number]: boolean } = {}
	for index: number, character: any in keyframe.characters do
		local record: any = Record.new()
		Record.read(character.record, 0, record, harness.limits)
		found[record.slot] = true

		local code: number = codes[index]
		local marked: boolean = bit32.extract(code, WITHHELD_BIT) == 1
		local kind: number = bit32.extract(code, 0, WITHHELD_BIT)

		if record.slot == culled then
			if not character.withheld or not marked or kind ~= PLAYER_CODE then
				return false, `The withheld player's kind byte is {code}, not a Player's with bit 7 set`
			elseif buffer.tostring(character.look) ~= harness:pack("slot", LOOK) then
				return false, "The moderator's keyframe dropped the withheld player's look"
			elseif buffer.tostring(character.held) ~= harness:pack("held", HELD) then
				return false, "The moderator's keyframe dropped the withheld player's held item"
			end
		elseif record.slot == seen then
			if character.withheld or marked then
				return false, "The moderator's keyframe marked a player the target is sent as withheld"
			elseif buffer.tostring(character.look) ~= harness:pack("slot", SEEN_LOOK) then
				return false, "The moderator's keyframe dropped the target's sent player's look"
			end
		end
	end

	if not found[culled] or not found[seen] then
		return false, "The moderator's keyframe left out the seen or the withheld player"
	end

	-- The target's own keyframe is its view alone, with no withheld player in it
	local own: any = Keyframe.read(Harness.Relay.keyframe(target.viewer.key))
	if #own.characters ~= 1 or own.characters[1].withheld then
		return false, `The target's keyframe holds {#own.characters} characters, or a withheld one`
	end

	local record: any = Record.new()
	Record.read(own.characters[1].record, 0, record, harness.limits)
	if record.slot ~= seen or own.sequence ~= target.newest then
		return false, "The target's keyframe is not its own view"
	end

	return true, nil
end
