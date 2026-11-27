--[[
    A relay block carries whole records under its fifth count and change
    records after them to its end, each read back where it lies and rebuilt
    against its baseline, and a tap block's bound lets it pass 896 B
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SEQUENCE: number = 7
local TICK: number = 1000
local START: vector = vector.create(100, 10, -200)
local PITCH_STEP: number = (math.pi / 2) / 127
local TAP_RECORDS: number = 60 -- Past the 55 a relay block holds
local WHOLE_TOP: number = 255 -- The most whole records a block's u8 count holds

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Change: any = globals.require(tread.Codec.Change)
	local Constants: any = globals.require(tread.Constants)
	local Record: any = globals.require(tread.Codec.Record)

	local function encode(slot: number, fields: { [string]: any }): buffer
		local record: { [string]: any } = Record.new()
		record.slot, record.generation, record.position = slot, 1, START
		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(16)
		Record.write(record, data, 0, Game.limits)

		return data
	end

	-- Two whole records, and three changes each against its slot's baseline: a walk, a still repeat and a turn
	local wholes: buffer = buffer.create(32)
	buffer.copy(wholes, 0, encode(50, {}))
	buffer.copy(wholes, 16, encode(51, { yaw = 1 }))

	local baselines: { buffer } = { encode(37, {}), encode(40, {}), encode(41, {}) }
	local currents: { buffer } = {
		encode(37, { position = START + vector.create(1.5, 0, -0.75) }),
		encode(40, {}),
		encode(41, { yaw = math.pi / 2, pitch = 10 * PITCH_STEP }),
	}

	local pool: buffer = buffer.create(48)
	local offsets: { number } = {}
	local lengths: { number } = {}
	local filled: number = 0
	for index: number, base: number in { 3, 20, 3 } do
		offsets[index] = filled
		lengths[index] = Change.write(currents[index], 0, baselines[index], 0, base, pool, filled)
		filled += lengths[index]
	end

	if lengths[1] ~= 8 or lengths[2] ~= 4 or lengths[3] ~= 7 then
		return false, `The changes took {lengths[1]}, {lengths[2]} and {lengths[3]} B, not 8, 4 and 7`
	end

	-- The changes named last first, so the block copies them in the order it is handed them
	local block: any = Block.new()
	block.sequence, block.tick = SEQUENCE, TICK
	block.reveals[1], block.revealCount = { slot = 50, generation = 1, kind = "Player" }, 1
	block.recordData, block.records, block.recordCount = wholes, { 16, 0 }, 2
	block.changeData, block.changeCount = pool, 3
	block.changeOffsets = { offsets[3], offsets[1], offsets[2] }
	block.changeLengths = { lengths[3], lengths[1], lengths[2] }

	local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
	local bytes: number = Block.write(block, data)
	local size: number = 9 + 3 + 2 * 16 + 8 + 4 + 7
	if bytes ~= size then
		return false, `The block filled {bytes} B, where its sections fill {size}`
	elseif buffer.readu8(data, 8) ~= 2 then
		return false, `The header counts {buffer.readu8(data, 8)} whole records, not 2`
	end

	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, data, 0, bytes)

	local read: any = Block.new()
	Block.read(exact, read)
	if read.recordCount ~= 2 or read.changeCount ~= 3 or read.changeData ~= exact then
		return false, `The block read back {read.recordCount} whole records and {read.changeCount} changes`
	elseif buffer.readu16(exact, read.records[1]) ~= Record.id(51, 1) then
		return false, "The whole records read back out of their order"
	end

	-- Each change where it lies, as long as it went, and rebuilt against its baseline into its current record
	for index: number, from: number in { 3, 1, 2 } do
		local at: number = read.changeOffsets[index]
		local rebuilt: buffer = buffer.create(16)

		if read.changeLengths[index] ~= lengths[from] then
			return false, `Change {index} read back {read.changeLengths[index]} B long, not {lengths[from]}`
		elseif buffer.readstring(exact, at, lengths[from]) ~= buffer.readstring(pool, offsets[from], lengths[from]) then
			return false, `Change {index} read back other bytes than it was written with`
		end

		Change.read(exact, at, baselines[from], 0, rebuilt, 0)
		if buffer.tostring(rebuilt) ~= buffer.tostring(currents[from]) then
			return false, `Change {index} rebuilt another record than the one it was made from`
		end
	end

	-- A block whose table names no changes, as one built by hand, writes as it did with its count 0
	local bare: any = Block.new()
	bare.recordData, bare.records, bare.recordCount = wholes, { 0 }, 1
	bare.changeCount, bare.changeData, bare.changeOffsets, bare.changeLengths = nil, nil, nil, nil
	if Block.write(bare, data) ~= 9 + 16 then
		return false, "A block with no change fields didn't write its header and one record"
	end

	-- A change handed with another length than its mask names
	block.changeLengths = { lengths[3] - 1, lengths[1], lengths[2] }
	local refused: boolean, why: string = Refuses("doesn't fill the 7 B its mask 24 names", Block.write, block, data)
	if not refused then
		return false, `A change of the wrong length was written: {why}`
	end

	-- A tap block of 60 whole records passes 896 B, so it is written and read only within a tap block's bound
	local tapPool: buffer = buffer.create((WHOLE_TOP + 1) * 16)
	local tapRecords: { number } = {}
	for index: number = 1, WHOLE_TOP + 1 do
		buffer.writeu16(tapPool, (index - 1) * 16, index)
		tapRecords[index] = (index - 1) * 16
	end

	local tap: any = Block.new()
	tap.recordData, tap.records, tap.recordCount = tapPool, tapRecords, TAP_RECORDS
	local tapData: buffer = buffer.create(Constants.TAP_BLOCK_BYTES)
	refused, why = Refuses("passes its 896 B", Block.write, tap, tapData)
	if not refused then
		return false, `A block of 60 records was written within a relay block's bound: {why}`
	end

	local tapBytes: number = Block.write(tap, tapData, Constants.TAP_BLOCK_BYTES)
	local tapExact: buffer = buffer.create(tapBytes)
	buffer.copy(tapExact, 0, tapData, 0, tapBytes)
	refused, why = Refuses("9 to 896 B, not 969", Block.read, tapExact, read)
	if tapBytes ~= 9 + TAP_RECORDS * 16 or not refused then
		return false, `A tap block of {tapBytes} B was read within a relay block's bound: {why}`
	end

	Block.read(tapExact, read, Constants.TAP_BLOCK_BYTES)
	if read.recordCount ~= TAP_RECORDS or read.changeCount ~= 0 or buffer.readu16(tapExact, read.records[60]) ~= 60 then
		return false, `A tap block read back {read.recordCount} records, its last out of place`
	end

	-- The whole records' u8 count holds 255, even within a tap block's bound
	tap.recordCount = WHOLE_TOP + 1
	refused, why = Refuses("at most 255 entries", Block.write, tap, tapData, Constants.TAP_BLOCK_BYTES)
	if not refused then
		return false, `256 whole records were written: {why}`
	end

	return true, nil
end
