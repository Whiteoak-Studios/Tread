--[[
    Decode reads each layout for its CODEC_VERSION with no game declarations,
    handing every block of game fields back as its packed bytes, and lean
    and the head offset as shares of the game's limits
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local CLOSE: number = 1e-9

-- A copy of length bytes of data from at
local function slice(data: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, data, at, length)

	return part
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
	local roblox: any = require("@lune/roblox")

	local layout: any = Fields.compile(Game.fields)
	local version: number = Constants.CODEC_VERSION

	-- A record, its state word unpacked beside it
	local record: { [string]: any } = Record.new()
	record.slot, record.generation = 300, 9
	record.position = vector.create(-100.5, 20.25, 7)
	record.platform = 3
	record.yaw = math.pi
	record.lean = -10 -- Half the fixture's 20° limit, so a share of -0.5 within a step
	record.word = 4 + 2 * 8 + 3 * 16384 -- Mantle, Downed, epoch parity 3

	local recordData: buffer = buffer.create(16)
	Record.write(record, recordData, 0, Game.limits)

	local decoded: { [string]: any } = Decode.decode(version, "record", recordData)
	local expected: { [string]: any } = {
		slot = 300,
		generation = 9,
		position = record.position,
		platform = 3,
		yaw = math.pi,
		pitch = 0,
		lean = -64 / 127,
		headYaw = 0,
		headPitch = 0,
		mode = "Mantle",
		posture = "Downed",
		sprint = false,
		aim = false,
		waterLevel = "Dry",
		jumps = 0,
		lands = 0,
		heavy = false,
		epoch = 3,
	}

	local differs: string? = Same(expected, decoded, "record", CLOSE)
	if differs then
		return false, differs
	end

	-- A command in Move's layout: Tread's 11 B, then its game fields behind their length
	local command: { [string]: any } = Command.new()
	command.forward, command.jump, command.headYaw = 1, true, 75
	command.fields = Game.high.command

	local wire: { [string]: any } = Command.wire()
	Command.write(command, wire, layout, Game.limits)

	local fieldsLength: number = buffer.len(wire.fields)
	local commandData: buffer = buffer.create(12 + fieldsLength)
	buffer.writei8(commandData, 1, wire.moveZ)
	buffer.writeu16(commandData, 2, wire.buttons)
	buffer.writei8(commandData, 9, wire.headYaw)
	buffer.writeu8(commandData, 11, fieldsLength)
	buffer.copy(commandData, 12, wire.fields)

	decoded = Decode.decode(version, "command", commandData)
	if decoded.forward ~= 1 or decoded.jump ~= true or decoded.headYaw ~= 1 or decoded.crouch ~= false then
		return false, "The command decoded with other fields than it was written with"
	end

	differs = Same(wire.fields, decoded.fields, "command fields")
	if differs then
		return false, differs
	end

	-- OwnerState, its two game blocks as their bytes
	local state: { [string]: any } = State.new()
	state.position = vector.create(1, 2, 3)
	state.moveMode = "Noclip"
	state.lean = 20
	state.fields = Game.high.server
	state.block = Game.high.rules

	local ownerData: buffer = buffer.create(96)
	local ownerLength: number = OwnerState.write(state, ownerData, 0, layout, Game.limits)
	local owner: buffer = slice(ownerData, 0, ownerLength)

	decoded = Decode.decode(version, "owner", owner)
	local server: buffer = slice(owner, 42, 2)
	local rules: buffer = slice(owner, 45, 3)
	if decoded.position ~= vector.create(1, 2, 3) or decoded.moveMode ~= "Noclip" or decoded.lean ~= 1 then
		return false, "OwnerState decoded with other fields than it was written with"
	elseif Same(server, decoded.fields, "server") or Same(rules, decoded.block, "rules") then
		return false, "OwnerState's game blocks didn't decode as their packed bytes"
	end

	-- The relay block and the withheld block, which carries looks and records alone
	local block: any = Block.new()
	block.sequence, block.tick = 2, 3
	block.reveals[1] = { slot = 1, generation = 2, kind = "Sleeper" }
	block.hides[1] = { slot = 4, generation = 5 }
	block.revealCount, block.hideCount = 1, 1
	block.looks[1] = {
		slot = 1,
		generation = 2,
		look = true,
		lookData = owner,
		lookAt = 42,
		lookLength = 2,
		held = true,
		heldData = owner,
		heldAt = 0,
		heldLength = 0,
	}
	block.lookCount = 1

	local stepData: buffer = buffer.create(10)
	Block.writeFootstep(
		{ at = vector.create(5, 6, 7), kind = "Jump", material = roblox.Enum.Material.Mud },
		stepData,
		0
	)
	block.footstepData, block.footsteps, block.footstepCount = stepData, { 0 }, 1
	block.recordData, block.records, block.recordCount = recordData, { 0 }, 1

	local scratch: buffer = buffer.create(896)
	local relay: buffer = slice(scratch, 0, Block.write(block, scratch))

	decoded = Decode.decode(version, "relay", relay)
	if
		decoded.sequence ~= 2
		or decoded.tick ~= 3
		or decoded.reveals[1].kind ~= "Sleeper"
		or decoded.hides[1].slot ~= 4
	then
		return false, "The relay block decoded with another header, reveal or hide"
	elseif Same(server, decoded.looks[1].look, "look") or buffer.len(decoded.looks[1].held) ~= 0 then
		return false, "The relay block's look entry didn't decode its parts as their bytes"
	elseif decoded.footsteps[1].kind ~= "Jump" or decoded.footsteps[1].material ~= roblox.Enum.Material.Mud then
		return false, "The relay block's footstep entry decoded as another"
	elseif Same(expected, decoded.records[1], "relay record", CLOSE) then
		return false, "The relay block's record decoded as another"
	end

	local refused: boolean, why: string =
		Refuses("no reveals, hides or footstep entries", Decode.decode, version, "withheld", relay)
	if not refused then
		return false, `A withheld block with reveals was decoded: {why}`
	end

	block.revealCount, block.hideCount, block.footstepCount = 0, 0, 0
	local withheld: buffer = slice(scratch, 0, Block.write(block, scratch))
	decoded = Decode.decode(version, "withheld", withheld)
	if #decoded.looks ~= 1 or #decoded.records ~= 1 or #decoded.reveals ~= 0 then
		return false, "The withheld block decoded other than its look and record"
	end

	-- The feed, its OwnerState decoded inside it
	local feedData: buffer = buffer.create(160)
	local feedLength: number = Feed.write(feedData, owner, 0, ownerLength, { command }, 1, Game.limits)
	decoded = Decode.decode(version, "feed", slice(feedData, 0, feedLength))
	if decoded.owner.moveMode ~= "Noclip" or #decoded.looks ~= 1 or decoded.looks[1].headYaw ~= 1 then
		return false, "The feed decoded with another OwnerState or look"
	end

	-- The keyframe, each character's record decoded
	local keyframe: buffer = Keyframe.write({
		hash = 77,
		tick = 8,
		sequence = 9,
		characters = { { kind = "Npc", withheld = true, record = recordData, look = server, held = rules } },
		platforms = { { id = 5, tick = 6 } },
	})

	decoded = Decode.decode(version, "keyframe", keyframe)
	local character: { [string]: any } = decoded.characters[1]
	if decoded.version ~= version or decoded.hash ~= 77 or decoded.platforms[1].tick ~= 6 then
		return false, "The keyframe decoded with another header or platform"
	elseif
		character.kind ~= "Npc"
		or not character.withheld
		or Same(expected, character.record, "keyframe record", CLOSE)
	then
		return false, "The keyframe's character decoded as another"
	end

	-- What the decoder refuses: a version it has no reader for, a layout it doesn't name, and what isn't a buffer
	local refusals: { { any } } = {
		{ "not 2", version + 1, "record", recordData },
		{ "not ghost", version, "ghost", recordData },
		{ "not a string", version, "record", "bytes" },
		{ "record is 16 B, not 15", version, "record", buffer.create(15) },
		{ "at least 12 B", version, "command", buffer.create(11) },
		{ "don't end", version, "command", slice(commandData, 0, buffer.len(commandData) - 1) },
	}

	for _, row: { any } in refusals do
		refused, why = Refuses(row[1], Decode.decode, row[2], row[3], row[4])
		if not refused then
			return false, `The decoder took what it should refuse with {row[1]}: {why}`
		end
	end

	return true, nil
end
