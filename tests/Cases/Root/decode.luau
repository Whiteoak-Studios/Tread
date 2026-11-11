--[[
    Tread.decode reads every layout the decoder covers with each position
    and direction crossed onto Vector3 and no vector left anywhere in what
    it hands back, and refuses a version or a kind it has no reader for
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SCRATCH_BYTES: number = 896 -- Past the largest layout built here
local PLAIN_COMMAND: number = 12 -- Tread's 11 B of a command and a u8 length of 0, with no game fields

-- A copy of length bytes of data from at
local function slice(data: buffer, at: number, length: number): buffer
	local part: buffer = buffer.create(length)
	buffer.copy(part, 0, data, at, length)

	return part
end

-- The path of the first vector left in a decoded table or one inside it, or nil when every one was crossed
local function stray(value: any, path: string): string?
	if type(value) == "vector" then
		return path
	elseif type(value) ~= "table" then
		return nil
	end

	for key: any, inner: any in value do
		local found: string? = stray(inner, `{path}.{tostring(key)}`)
		if found then
			return found
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Tread: any = globals.require(tread)
	local Block: any = globals.require(tread.Codec.Block)
	local Command: any = globals.require(tread.Codec.Command)
	local Constants: any = globals.require(tread.Constants)
	local Feed: any = globals.require(tread.Codec.Feed)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Keyframe: any = globals.require(tread.Codec.Keyframe)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Record: any = globals.require(tread.Codec.Record)
	local State: any = globals.require(tread.Step.State)

	local Vector3: any = roblox.Vector3
	local version: number = Tread.CODEC_VERSION
	local layout: any = Fields.compile(Game.fields)

	if version ~= Constants.CODEC_VERSION then
		return false, `Tread.CODEC_VERSION is {version}, not the codec's {Constants.CODEC_VERSION}`
	end

	-- A record at a place each axis's precision holds exactly
	local record: { [string]: any } = Record.new()
	record.slot, record.generation = 300, 9
	record.position = vector.create(-100.5, 20.25, 7)

	local recordData: buffer = buffer.create(Constants.RECORD_BYTES)
	Record.write(record, recordData, 0, Game.limits)

	-- OwnerState, its game blocks from the fixture's values
	local state: { [string]: any } = State.new()
	state.position = vector.create(1, 2, 3)
	state.velocity = vector.create(4, 0, -2)
	state.fields = Game.high.server
	state.block = Game.high.rules

	local scratch: buffer = buffer.create(SCRATCH_BYTES)
	local owner: buffer = slice(scratch, 0, OwnerState.write(state, scratch, 0, layout, Game.limits))

	-- A relay block carrying the record and one footstep entry
	local stepData: buffer = buffer.create(Constants.FOOTSTEP_BYTES)
	Block.writeFootstep(
		{ at = vector.create(5, 6, 7), kind = "Walk", material = roblox.Enum.Material.Mud },
		stepData,
		0
	)

	local block: any = Block.new()
	block.sequence, block.tick = 2, 3
	block.footstepData, block.footsteps, block.footstepCount = stepData, { 0 }, 1
	block.recordData, block.records, block.recordCount = recordData, { 0 }, 1
	local relay: buffer = slice(scratch, 0, Block.write(block, scratch))

	block.footstepCount = 0
	local withheld: buffer = slice(scratch, 0, Block.write(block, scratch))

	local command: any = Command.new()
	local feedData: buffer = buffer.create(SCRATCH_BYTES)
	local feed: buffer =
		slice(feedData, 0, Feed.write(feedData, owner, 0, buffer.len(owner), { command }, 1, Game.limits))

	local keyframe: buffer = Keyframe.write({
		hash = 77,
		tick = 8,
		sequence = 9,
		characters = {
			{ kind = "Npc", withheld = false, record = recordData, look = buffer.create(0), held = buffer.create(0) },
		},
		platforms = {},
		gravity = 68.1,
	})

	local expected: any = Vector3.new(-100.5, 20.25, 7)

	-- Each layout, and the position it must hand back as a Vector3
	local rows: { { kind: string, data: buffer, position: (decoded: any) -> any, at: any } } = {
		{
			kind = "record",
			data = recordData,
			position = function (decoded: any): any
				return decoded.position
			end,
			at = expected,
		},
		{
			kind = "owner",
			data = owner,
			position = function (decoded: any): any
				return decoded.velocity
			end,
			at = Vector3.new(4, 0, -2),
		},
		{
			kind = "relay",
			data = relay,
			position = function (decoded: any): any
				return decoded.footsteps[1].at
			end,
			at = Vector3.new(5, 6, 7),
		},
		{
			kind = "withheld",
			data = withheld,
			position = function (decoded: any): any
				return decoded.records[1].position
			end,
			at = expected,
		},
		{
			kind = "feed",
			data = feed,
			position = function (decoded: any): any
				return decoded.owner.position
			end,
			at = Vector3.new(1, 2, 3),
		},
		{
			kind = "keyframe",
			data = keyframe,
			position = function (decoded: any): any
				return decoded.characters[1].record.position
			end,
			at = expected,
		},
	}

	for _, row in rows do
		local decoded: any = Tread.decode(version, row.kind, row.data)
		local position: any = row.position(decoded)
		local left: string? = stray(decoded, row.kind)

		if typeof(position) ~= "Vector3" or position ~= row.at then
			return false, `Tread.decode of a {row.kind} gave {position}, a {typeof(position)}, not the Vector3 {row.at}`
		elseif left then
			return false, `Tread.decode of a {row.kind} left a vector at {left}`
		end
	end

	-- A command carries no position, and its game fields come back as their bytes
	local decoded: any = Tread.decode(version, "command", buffer.create(PLAIN_COMMAND))
	if decoded.forward ~= 0 or typeof(decoded.fields) ~= "buffer" or buffer.len(decoded.fields) ~= 0 then
		return false, "Tread.decode of a command with no game fields gave other fields than it holds"
	end

	-- What it refuses: a version it has no reader for and a layout it doesn't name
	local refusals: { { any } } = {
		{ `not {version + 1}`, version + 1, "record", recordData },
		{ "not ghost", version, "ghost", recordData },
	}

	for _, row: { any } in refusals do
		local refused: boolean, why: string = Refuses(row[1], Tread.decode, row[2], row[3], row[4])
		if not refused then
			return false, `Tread.decode took what it should refuse with {row[1]}: {why}`
		end
	end

	return true, nil
end
