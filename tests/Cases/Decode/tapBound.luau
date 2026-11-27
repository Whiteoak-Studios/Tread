--[[
    A tap frame's block may pass a relay block's 896 B up to the 65,535 its
    u16 length holds, since each change goes to a tap as its whole record,
    while the relay kind still refuses a block past 896 B
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RECORDS: number = 60 -- Past the 55 a relay block holds
local TICK: number = 12

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = globals.require(tread.Codec.Block)
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)
	local Record: any = globals.require(tread.Codec.Record)
	local Tap: any = globals.require(tread.Codec.Tap)

	-- 60 whole records, each of its own slot, in one block of 969 B
	local pool: buffer = buffer.create(RECORDS * 16)
	local block: any = Block.new()
	local reasons: { string } = {}
	for index: number = 1, RECORDS do
		local record: any = Record.new()
		record.slot, record.generation = index, 1
		Record.write(record, pool, (index - 1) * 16, { lean = 1, headCone = 1 })

		block.records[index] = (index - 1) * 16
		reasons[index] = "Teammate"
	end

	block.recordData, block.recordCount = pool, RECORDS

	local scratch: buffer = buffer.create(Constants.TAP_BLOCK_BYTES)
	local bytes: number = Block.write(block, scratch, Constants.TAP_BLOCK_BYTES)
	local big: buffer = buffer.create(bytes)
	buffer.copy(big, 0, scratch, 0, bytes)

	local body: buffer = buffer.create(Tap.blockBytes(bytes, RECORDS))
	local filled: number = Tap.writeBlock(body, 0, big, reasons, RECORDS)
	local frame: buffer = Tap.frame(TICK, 1, body, filled, nil, 0, 0)

	local read: any = Tap.read(frame)
	if bytes ~= 9 + RECORDS * 16 or buffer.len(read.blocks[1].data) ~= bytes then
		return false, `The frame carried its {bytes} B block as {buffer.len(read.blocks[1].data)} B`
	end

	local decoded: any = Decode.decode(Constants.CODEC_VERSION, "tap", frame)
	local records: { any } = decoded.blocks[1].records
	if #records ~= RECORDS or records[RECORDS].slot ~= RECORDS or records[RECORDS].reason ~= "Teammate" then
		return false, `The frame's block decoded {#records} records, its last as slot {records[#records].slot}`
	end

	-- The relay kind keeps a relay block's bound, and a frame's block stops at its u16 length's top
	local refused: boolean, why: string =
		Refuses("9 to 896 B, not 969", Decode.decode, Constants.CODEC_VERSION, "relay", big)
	if not refused then
		return false, `A relay block of 969 B was decoded: {why}`
	end

	refused, why = Refuses("9 to 65535 B, not 65536", Tap.writeBlock, body, 0, buffer.create(65536), {}, 0)
	if not refused then
		return false, `A frame's block of 65,536 B was written: {why}`
	end

	return true, nil
end
