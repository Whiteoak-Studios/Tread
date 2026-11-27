--[[
    Decode lists a relay block's change records with no baseline: each one's
    slot, generation, base and mask, X, Z and a Y step as differences in
    studs, a whole Y, yaw, pitch and the state word as a record reads them
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local CLOSE: number = 1e-9
local START: vector = vector.create(100, 10, -200)
local PITCH_STEP: number = (math.pi / 2) / 127
local AIR: number = 1 -- The state word's Air mode
local ONE_JUMP: number = 2 ^ 9 -- One on its jump counter, in bits 9 and 10

-- The state word above, unpacked as Decode gives a record's
local JUMPED: { [string]: any } = {
	mode = "Air",
	posture = "Stand",
	sprint = false,
	aim = false,
	waterLevel = "Dry",
	jumps = 1,
	lands = 0,
	heavy = false,
	epoch = 0,
}

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Change: any = globals.require(tread.Codec.Change)
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)
	local Record: any = globals.require(tread.Codec.Record)

	local function encode(slot: number, fields: { [string]: any }): buffer
		local record: { [string]: any } = Record.new()
		record.slot, record.generation, record.position = slot, 2, START
		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(16)
		Record.write(record, data, 0, Game.limits)

		return data
	end

	-- A walk, a still repeat, a turn, a hop with its jump and lean, and a climb past a Y step
	local hop: buffer = encode(42, { position = START + vector.create(0, 0.5, 0), word = AIR + ONE_JUMP, lean = 10 })
	local rows: { { any } } = {
		{ 37, 3, { position = START + vector.create(1.5, 0, -0.75) } },
		{ 40, 20, {} },
		{ 41, 3, { yaw = math.pi / 2, pitch = 10 * PITCH_STEP } },
		{ 42, 5, hop },
		{ 43, 31, { position = START + vector.create(0, 20, 0) } },
	}

	local pool: buffer = buffer.create(5 * 16)
	local block: any = Block.new()
	local filled: number = 0
	for index: number, row: { any } in rows do
		local current: buffer = typeof(row[3]) == "buffer" and row[3] or encode(row[1], row[3])
		local length: number = Change.write(current, 0, encode(row[1], {}), 0, row[2], pool, filled)

		block.changeOffsets[index], block.changeLengths[index] = filled, length
		filled += length
	end

	block.changeData, block.changeCount = pool, #rows

	local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local bytes: number = Block.write(block, scratch)
	local relay: buffer = buffer.create(bytes)
	buffer.copy(relay, 0, scratch, 0, bytes)

	local expected: { { [string]: any } } = {
		{ slot = 37, generation = 2, base = 3, mask = 3, dx = 1.5, dz = -0.75 },
		{ slot = 40, generation = 2, base = 20, mask = 0 },
		{ slot = 41, generation = 2, base = 3, mask = 24, yaw = math.pi / 2, pitch = 10 * PITCH_STEP },
		{ slot = 42, generation = 2, base = 5, mask = 100, dy = 0.5, word = JUMPED, last = buffer.readu8(hop, 15) },
		{ slot = 43, generation = 2, base = 31, mask = 128, y = 30 },
	}

	local decoded: any = Decode.decode(Constants.CODEC_VERSION, "relay", relay)
	local differs: string? = Same(expected, decoded.changes, "changes", CLOSE)
	if differs then
		return false, differs
	elseif #decoded.records ~= 0 then
		return false, `The changes decoded beside {#decoded.records} whole records`
	end

	-- A block with no change records lists none
	block.changeCount = 0
	local bare: buffer = buffer.create(Block.write(block, scratch))
	buffer.copy(bare, 0, scratch, 0, buffer.len(bare))
	if #Decode.decode(Constants.CODEC_VERSION, "relay", bare).changes ~= 0 then
		return false, "A block with no change records decoded with some"
	end

	return true, nil
end
