--[[
    Tread.decode reads a tap frame and a snapshot with every position
    crossed onto Vector3, a record's beside its send reason and the
    OwnerState's beside its character, and no vector left anywhere
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"

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
	local Constants: any = globals.require(tread.Constants)
	local Fields: any = globals.require(tread.Codec.Fields)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Record: any = globals.require(tread.Codec.Record)
	local State: any = globals.require(tread.Step.State)
	local Tap: any = globals.require(tread.Codec.Tap)

	local layout: any = Fields.compile(Game.fields)
	local version: number = Tread.CODEC_VERSION

	local recordData: buffer = buffer.create(Constants.RECORD_BYTES)
	local record: any = Record.new()
	record.slot, record.generation = 30, 1
	record.position = vector.create(-100.5, 20.25, 7)
	Record.write(record, recordData, 0, Game.limits)

	local block: any = Block.new()
	block.recordData, block.records, block.recordCount = recordData, { 0 }, 1

	local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local relay: buffer = slice(scratch, 0, Block.write(block, scratch))

	local state: any = State.new()
	state.position = vector.create(1, 2, 3)
	state.fields = Game.high.server
	state.block = Game.high.rules
	local owner: buffer = slice(scratch, 0, OwnerState.write(state, scratch, 0, layout, Game.limits))

	local body: buffer = buffer.create(Constants.MAX_RELAY_BYTES * 2)
	local filled: number = Tap.writeBlock(body, 0, relay, { "Teammate" }, 1)
	local frame: buffer = Tap.frame(5, 1, body, filled, owner, buffer.len(owner), Record.id(4, 1))

	local decoded: any = Tread.decode(version, "tap", frame)
	local position: any = decoded.blocks[1].records[1].position
	local left: string? = stray(decoded, "tap")

	if typeof(position) ~= "Vector3" or position ~= roblox.Vector3.new(-100.5, 20.25, 7) then
		return false, `Tread.decode of a tap gave the record's position as {position}, a {typeof(position)}`
	elseif decoded.blocks[1].records[1].reason ~= "Teammate" then
		return false, "Tread.decode of a tap dropped the record's send reason"
	elseif typeof(decoded.owner.position) ~= "Vector3" or decoded.owner.slot ~= 4 then
		return false, "Tread.decode of a tap left the OwnerState's position a vector or dropped its character"
	elseif left then
		return false, `Tread.decode of a tap left a vector at {left}`
	end

	local snapshot: buffer = Tap.writeSnapshot({
		hash = Fields.hash(layout),
		slots = {
			{ slot = 4, generation = 1, kind = "Player", rig = "A", look = buffer.create(0), held = buffer.create(0) },
		},
	})

	decoded = Tread.decode(version, "snapshot", snapshot)
	if decoded.hash ~= Fields.hash(layout) or decoded.slots[1].kind ~= "Player" then
		return false, "Tread.decode of a snapshot gave another hash or slot"
	end

	return true, nil
end
