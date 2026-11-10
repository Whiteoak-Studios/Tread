--[[
    Decode reads a tap frame, each block's records with their 3-bit send
    reasons packed low bit first and the OwnerState with its character, view
    lag and looks as the feed packs them, a snapshot of slots with their
    looks and a keyframe's own character, and refuses what is none of them
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local CLOSE: number = 1e-9
local TICK: number = 70000 -- Past a u16, so the frame carries its low 16 bits
local OWNER_SLOT: number = 12
local OWNER_GENERATION: number = 2
local FRAME_HEADER_BYTES: number = 4
local LENGTH_BYTES: number = 2
local NPC_CODE: number = 4
local HIDDEN_CODE: number = 5
local CODE_BITS: number = 3
local LAG: number = 65535 -- Milliseconds, the u16's top
local LOOK_BYTES: number = 6
local YAW_STEP: number = 2 * math.pi / 65536
local PITCH_STEP: number = (math.pi / 2) / 16384
local HEAD_STEP: number = 1 / 127 -- A head offset's step as a share of the cone, as the decoder gives it

-- Two stepped looks, newest first, the head offsets in degrees at the edges of the game's 75° cone
local LOOKS: { { number } } = {
	{ 1.5, -0.25, 75, -75 },
	{ 2 * math.pi - YAW_STEP, math.pi / 2, 10, 0 },
}

-- A copy of length bytes of data from at
local function slice(data: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, data, at, length)

	return part
end

-- A copy of data with one byte changed
local function patched(data: buffer, at: number, value: number): buffer
	local copy: buffer = slice(data, 0, buffer.len(data))
	buffer.writeu8(copy, at, value)

	return copy
end

-- A copy of data with a zero byte after its end
local function longer(data: buffer): buffer
	local copy: buffer = buffer.create(buffer.len(data) + 1)
	buffer.copy(copy, 0, data)

	return copy
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Command: any = globals.require(tread.Codec.Command)
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)
	local Feed: any = globals.require(tread.Codec.Feed)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Keyframe: any = globals.require(tread.Codec.Keyframe)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Record: any = globals.require(tread.Codec.Record)
	local State: any = globals.require(tread.Step.State)
	local Tap: any = globals.require(tread.Codec.Tap)

	local layout: any = Fields.compile(Game.fields)
	local version: number = Constants.CODEC_VERSION

	-- Two records, an NPC's and a hidden player's, in one relay block
	local records: buffer = buffer.create(2 * Constants.RECORD_BYTES)
	for index: number, slot: number in { 40, 41 } do
		local record: any = Record.new()
		record.slot, record.generation = slot, 1
		record.position = vector.create(slot, 2, 3)
		Record.write(record, records, (index - 1) * Constants.RECORD_BYTES, Game.limits)
	end

	local block: any = Block.new()
	block.sequence, block.tick = 9, 10
	block.recordData, block.records, block.recordCount = records, { 0, Constants.RECORD_BYTES }, 2

	local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local relay: buffer = slice(scratch, 0, Block.write(block, scratch))

	block.recordCount = 0
	local bare: buffer = slice(scratch, 0, Block.write(block, scratch))

	-- An OwnerState for the frame's owner
	local state: any = State.new()
	state.position = vector.create(1, 2, 3)
	state.fields = Game.high.server
	state.block = Game.high.rules
	local ownerData: buffer = buffer.create(Constants.MAX_OWNER_STATE)
	local owner: buffer = slice(ownerData, 0, OwnerState.write(state, ownerData, 0, layout, Game.limits))

	local body: buffer = buffer.create(2 * Constants.MAX_RELAY_BYTES)
	local filled: number = Tap.writeBlock(body, 0, relay, { "Npc", "Hidden" }, 2)
	if filled ~= Tap.blockBytes(buffer.len(relay), 2) then
		return false, `writeBlock filled {filled} B, not the {Tap.blockBytes(buffer.len(relay), 2)} blockBytes gives`
	end

	filled = Tap.writeBlock(body, filled, bare, {}, 0)

	local commands: { any } = {}
	for _, look: { number } in LOOKS do
		local command: any = Command.new()
		command.yaw, command.pitch, command.headYaw, command.headPitch = look[1], look[2], look[3], look[4]
		table.insert(commands, command)
	end

	local id: number = Record.id(OWNER_SLOT, OWNER_GENERATION)
	local frame: buffer =
		Tap.frame(TICK, 2, body, filled, owner, buffer.len(owner), id, LAG, commands, #commands, Game.limits)

	-- After the OwnerState its lag, then the look list exactly as a feed of the same commands carries it
	local ownerAt: number = FRAME_HEADER_BYTES + filled
	local lagAt: number = ownerAt + 1 + 2 + buffer.len(owner)
	local list: number = 1 + #commands * LOOK_BYTES
	local feed: buffer = buffer.create(1 + list)
	Feed.write(feed, owner, 0, 0, commands, #commands, Game.limits)

	if buffer.len(frame) ~= lagAt + 2 + list then
		return false, `The frame is {buffer.len(frame)} B, where its parts fill {lagAt + 2 + list}`
	elseif buffer.readu16(frame, lagAt) ~= LAG then
		return false, `The frame's view lag is {buffer.readu16(frame, lagAt)} ms, not {LAG}`
	elseif buffer.readstring(frame, lagAt + 2, list) ~= buffer.readstring(feed, 1, list) then
		return false, "The frame's look list is not the feed's look list for the same commands"
	end

	-- The two reasons pack into one byte, Npc in its low 3 bits and Hidden in the 3 above, the rest 0
	local reasonsAt: number = FRAME_HEADER_BYTES + LENGTH_BYTES + buffer.len(relay)
	local packed: number = NPC_CODE + HIDDEN_CODE * 2 ^ CODE_BITS
	if buffer.readu8(frame, reasonsAt) ~= packed then
		return false, `The reasons byte is {buffer.readu8(frame, reasonsAt)}, not {packed}`
	elseif buffer.readu16(frame, 0) ~= TICK % 2 ^ 16 or buffer.readu16(frame, 2) ~= 2 then
		return false, "The frame's header holds another tick or block count"
	end

	local decoded: any = Decode.decode(version, "tap", frame)
	local first: any = decoded.blocks[1]
	if decoded.tick ~= TICK % 2 ^ 16 or #decoded.blocks ~= 2 then
		return false, "The frame decoded with another tick or block count"
	elseif first.sequence ~= 9 or #first.records ~= 2 or #decoded.blocks[2].records ~= 0 then
		return false, "The frame's blocks decoded as others"
	elseif first.records[1].reason ~= "Npc" or first.records[2].reason ~= "Hidden" then
		return false, `The records' reasons decoded as {first.records[1].reason} and {first.records[2].reason}`
	elseif
		first.records[2].slot ~= 41 or vector.magnitude(first.records[2].position - vector.create(41, 2, 3)) > CLOSE
	then
		return false, "The frame's second record decoded as another"
	end

	local decodedOwner: any = decoded.owner
	if
		not decodedOwner
		or decodedOwner.slot ~= OWNER_SLOT
		or decodedOwner.generation ~= OWNER_GENERATION
		or decodedOwner.position ~= vector.create(1, 2, 3)
	then
		return false, "The frame's OwnerState decoded without its character or with another position"
	elseif decodedOwner.lag ~= LAG or #decodedOwner.looks ~= #LOOKS then
		return false, `The frame's owner decoded with {decodedOwner.lag} ms of lag and {#decodedOwner.looks} looks`
	end

	-- Each look newest first at the feed's precision, its head offset a share of the cone as the feed decodes it
	for index: number, look: { number } in LOOKS do
		local back: any = decodedOwner.looks[index]
		local wanted: { number } = { look[1], look[2], look[3] / Game.limits.headCone, look[4] / Game.limits.headCone }
		local read: { number } = { back.yaw, back.pitch, back.headYaw, back.headPitch }
		local steps: { number } = { YAW_STEP, PITCH_STEP, HEAD_STEP, HEAD_STEP }

		for part: number = 1, 4 do
			if math.abs(read[part] - wanted[part]) > steps[part] / 2 + CLOSE then
				return false, `Look {index} part {part} decoded as {read[part]}, not within a step of {wanted[part]}`
			end
		end
	end

	-- A frame with no block and no OwnerState is 5 B, and lag and looks never go without an OwnerState
	local empty: buffer = Tap.frame(3, 0, body, 0, nil, 0, 0)
	local bare: buffer = Tap.frame(3, 0, body, 0, nil, 0, 0, LAG, commands, #commands, Game.limits)
	decoded = Decode.decode(version, "tap", empty)
	if buffer.len(empty) ~= FRAME_HEADER_BYTES + 1 or #decoded.blocks ~= 0 or decoded.owner ~= nil then
		return false, "An empty frame took other bytes or decoded with a block or an OwnerState"
	elseif buffer.tostring(bare) ~= buffer.tostring(empty) then
		return false, "A frame with no OwnerState carried the lag and looks it was handed"
	end

	-- An OwnerState with no lag or looks handed carries a lag of 0 and no looks
	local still: any = Decode.decode(version, "tap", Tap.frame(3, 0, body, 0, owner, buffer.len(owner), id)).owner
	if not still or still.lag ~= 0 or #still.looks ~= 0 then
		return false, "A frame handed no lag or looks decoded with some"
	end

	-- A keyframe's own character, by its id, slot and generation, and none at all
	local keyframe: buffer = Keyframe.write({
		hash = 1,
		tick = 2,
		sequence = 3,
		characters = {},
		platforms = {},
		own = { id = id, look = buffer.fromstring("ab"), held = buffer.fromstring("c") },
	})

	local nobody: buffer = Keyframe.write({ hash = 1, tick = 2, sequence = 3, characters = {}, platforms = {} })
	local own: any = Decode.decode(version, "keyframe", keyframe).own
	local none: any = Decode.decode(version, "keyframe", nobody)
	if not own or own.id ~= id or own.slot ~= OWNER_SLOT or own.generation ~= OWNER_GENERATION then
		return false, "The keyframe's own character decoded with another id, slot or generation"
	elseif buffer.tostring(own.look) ~= "ab" or buffer.tostring(own.held) ~= "c" then
		return false, "The keyframe's own look and held item decoded as other bytes"
	elseif none.own ~= nil then
		return false, "A keyframe with no own character decoded with one"
	end

	-- A snapshot slot, its id the slot and generation, its kind and rig codes, its look and an empty held item
	local look: buffer = buffer.fromstring("ab")
	local snapshot: buffer = Tap.writeSnapshot({
		hash = 99,
		slots = { { slot = 5, generation = 3, kind = "Sleeper", rig = "B", look = look, held = buffer.create(0) } },
	})

	-- The version, the hash, the count, the id, the kind and rig codes, the look behind its length and the held item's
	local expected: string = "\1\0\99\0\0\0\1\0\5\48\3\1\2ab\0"
	if buffer.tostring(snapshot) ~= expected then
		return false, "The snapshot's bytes are not its layout's"
	end

	decoded = Decode.decode(version, "snapshot", snapshot)
	local slot: any = decoded.slots[1]
	if decoded.version ~= version or decoded.hash ~= 99 or #decoded.slots ~= 1 then
		return false, "The snapshot decoded with another header"
	elseif slot.slot ~= 5 or slot.generation ~= 3 or slot.kind ~= "Sleeper" or slot.rig ~= "B" then
		return false, "The snapshot's slot decoded as another"
	elseif buffer.tostring(slot.look) ~= "ab" or buffer.len(slot.held) ~= 0 then
		return false, "The snapshot's look and held item decoded as other bytes"
	end

	-- What the layouts refuse, a malformed look list among them: more looks than a Move, or more than its bytes hold
	local countAt: number = lagAt + 2
	local refusals: { { any } } = {
		{ "has no reason", "tap", patched(frame, reasonsAt, 7 + HIDDEN_CODE * 2 ^ CODE_BITS) },
		{ "pad their last byte", "tap", patched(frame, reasonsAt, packed + 2 ^ (2 * CODE_BITS)) },
		{ "ends inside", "tap", slice(frame, 0, lagAt + 1) },
		{ "at most 8 looks", "tap", patched(frame, countAt, 9) },
		{ "looks pass its", "tap", patched(frame, countAt, #LOOKS + 1) },
		{ "looks pass its", "tap", slice(frame, 0, buffer.len(frame) - 1) },
		{ "past its OwnerState", "tap", patched(frame, countAt, #LOOKS - 1) },
		{ "past its OwnerState", "tap", longer(frame) },
		{ "past its OwnerState", "tap", longer(empty) },
		{ "no own character", "keyframe", patched(longer(nobody), 15, 1) },
		{ "read only by that version", "snapshot", patched(snapshot, 0, version + 1) },
		{ "has no value", "snapshot", patched(snapshot, 10, 9) },
		{ "past its last slot", "snapshot", longer(snapshot) },
	}

	for _, row: { any } in refusals do
		local refused: boolean, why: string = Refuses(row[1], Decode.decode, version, row[2], row[3])
		if not refused then
			return false, `The decoder took what it should refuse with {row[1]}: {why}`
		end
	end

	local ghost: any = { slot = 1, generation = 1, kind = "Ghost", rig = "A", look = look, held = look }
	local writes: { { any } } = {
		{
			"one of the 7",
			function ()
				Tap.writeBlock(body, 0, relay, { "Visible", "Npc" }, 2)
			end,
		},
		{
			"8 to 896 B",
			function ()
				Tap.writeBlock(body, 0, buffer.create(4), {}, 0)
			end,
		},
		{
			"Player, Npc, Body or Sleeper",
			function ()
				Tap.writeSnapshot({ hash = 0, slots = { ghost } })
			end,
		},
		{
			"view lag is a whole 0 to 65535 ms",
			function ()
				Tap.frame(3, 0, body, 0, owner, buffer.len(owner), id, LAG + 1)
			end,
		},
		{
			"view lag is a whole 0 to 65535 ms",
			function ()
				Tap.frame(3, 0, body, 0, owner, buffer.len(owner), id, 1.5)
			end,
		},
		{
			"0 to 8 looks",
			function ()
				local nine: { any } = table.clone(commands)
				for _ = #nine + 1, 9 do
					table.insert(nine, Command.new())
				end

				Tap.frame(3, 0, body, 0, owner, buffer.len(owner), id, 0, nine, 9, Game.limits)
			end,
		},
		{
			"need their commands and the game's limits",
			function ()
				Tap.frame(3, 0, body, 0, owner, buffer.len(owner), id, 0, commands, 1)
			end,
		},
	}

	for _, row: { any } in writes do
		local refused: boolean, why: string = Refuses(row[1], row[2])
		if not refused then
			return false, `A writer took what it should refuse with {row[1]}: {why}`
		end
	end

	return true, nil
end
