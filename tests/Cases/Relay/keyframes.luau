--[[
    A keyframe holds a viewer's current view whole: the declarations' hash,
    the relay tick, its newest sequence, every character it is sent, idle
    or moving, with its kind, newest record, look and held item, and the
    platforms passed in, and nothing it is not sent
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local KEYFRAME: string = "src/Codec/Keyframe.luau"
local RECORD: string = "src/Codec/Record.luau"
local QUANTUM: number = 1 / 64
local LOOK: { [string]: any } = { leg = 40, shirt = 2 }
local HELD: { [string]: any } = { item = 9 }
local PLATFORMS: { { id: number, tick: number } } = { { id = 3, tick = 777 } }
local WRAP: number = 2 ^ 16

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Fields: any = Environment.load(FIELDS)
	local Keyframe: any = Environment.load(KEYFRAME)
	local Record: any = Environment.load(RECORD)

	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local stranger: any = harness:viewer("Stranger")
	stranger.viewer.position = vector.create(5000, 0, 0)

	local moving: number = harness:spawn("Player", vector.create(10, 0, 0))
	local idle: number = harness:spawn("Player", vector.create(-40, 0, 5))
	local npc: number = harness:spawn("Npc", vector.create(0, 0, 60))
	local hidden: number = harness:spawn("Player", vector.create(30, 0, 30))
	harness:hide(client, hidden, true)

	Harness.Relay.setLook(moving, LOOK)
	harness.states[moving].held = table.clone(HELD)

	for tick: number = 1, 30 do
		harness.states[moving].position = vector.create(10 + tick, 0, 0)
		harness:run()
	end

	local keyframe: any = Keyframe.read(Harness.Relay.keyframe(client.viewer.key, PLATFORMS))
	if keyframe.hash ~= Fields.hash(harness.layout) then
		return false, "The keyframe's hash is not the declarations'"
	elseif keyframe.tick ~= harness.tick % WRAP or keyframe.sequence ~= client.newest then
		return false, `The keyframe names tick {keyframe.tick} and sequence {keyframe.sequence}, not the last ones`
	elseif #keyframe.platforms ~= 1 or keyframe.platforms[1].id ~= 3 or keyframe.platforms[1].tick ~= 777 then
		return false, "The keyframe dropped the platform it was handed"
	end

	local expected: { [number]: string } = { [moving] = "Player", [idle] = "Player", [npc] = "Npc" }
	local found: { [number]: boolean } = {}

	for _, character: any in keyframe.characters do
		local record: any = Record.new()
		Record.read(character.record, 0, record, harness.limits)

		if record.slot == hidden then
			return false, "The keyframe held a character anti-ESP hides from the viewer"
		elseif expected[record.slot] ~= character.kind then
			return false, `The keyframe holds slot {record.slot} as a {character.kind}`
		elseif vector.magnitude(record.position - harness.states[record.slot].position) > QUANTUM then
			return false, `The keyframe's record for slot {record.slot} is not its newest`
		end

		found[record.slot] = true

		if record.slot == moving then
			if buffer.tostring(character.look) ~= harness:pack("slot", LOOK) then
				return false, "The keyframe dropped the dressed character's look"
			elseif buffer.tostring(character.held) ~= harness:pack("held", HELD) then
				return false, "The keyframe dropped the dressed character's held item"
			end
		elseif buffer.len(character.look) ~= 0 or buffer.len(character.held) ~= 0 then
			return false, `The keyframe gave slot {record.slot}, never dressed, a look or a held item`
		end
	end

	for slot: number in expected do
		if not found[slot] then
			return false, `The keyframe left out slot {slot}, which the viewer is sent`
		end
	end

	local empty: any = Keyframe.read(Harness.Relay.keyframe(stranger.viewer.key))
	if #empty.characters ~= 0 or empty.sequence ~= 0 or #empty.platforms ~= 0 then
		return false, "A viewer sent nothing got a keyframe with characters or a sequence in it"
	end

	return true, nil
end
