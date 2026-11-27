--[[
    With relay.changes on, a tap frame's blocks hold whole records alone,
    each change expanded to the record the viewer's client decoded, with a
    reason for each, so a block full of changes passes 896 B in the frame
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TAP: string = "src/Codec/Tap.luau"
local BLOCK: string = "src/Codec/Block.luau"
local CONSTANTS: string = "src/Constants.luau"
local CROWD: number = 120 -- Enough small changes to fill a block past what their whole records would
local RUNS: number = 4
local STEP: vector = vector.create(0.25, 0, 0) -- What each target walks a run, so each has a record every run
local ROW: number = 12 -- Targets a row of the crowd holds

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Tap: any = Environment.load(TAP)
	local Block: any = Environment.load(BLOCK)
	local Constants: any = Environment.load(CONSTANTS)

	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")

	local slots: { number } = {}
	for index: number = 0, CROWD - 1 do
		table.insert(slots, harness:spawn("Player", vector.create(index % ROW * 2, 0, index // ROW * 2 + 5)))
	end

	local frames: { buffer } = {}
	local stop: () -> () = Harness.Taps.observe(client.viewer.key, function (_: number, data: buffer)
		table.insert(frames, data)
	end)

	local passed: number = 0
	for run: number = 1, RUNS do
		for _, slot: number in slots do
			harness.states[slot].position += STEP
		end

		harness:run()

		local seen: any = client.seen
		local frame: any = Tap.read(frames[run])
		if #frame.blocks ~= #seen.blocks then
			return false, `Run {run}'s frame carried {#frame.blocks} blocks, where the viewer read {#seen.blocks}`
		end

		-- The client's records run block by block, each block's whole records and then its changes decoded
		local at: number = 0
		for index: number, part: any in frame.blocks do
			local block: any = Block.new()
			Block.read(part.data, block, Constants.TAP_BLOCK_BYTES)

			local read: { number } = seen.blocks[index].records
			if block.changeCount ~= 0 then
				return false, `Run {run}'s frame block {index} carried {block.changeCount} change records`
			elseif block.recordCount ~= #read or #part.reasons ~= #read then
				return false, `Run {run}'s frame block {index} held {block.recordCount} records, the client {#read}`
			end

			for record: number = 1, block.recordCount do
				local bytes: string = buffer.readstring(part.data, block.records[record], Constants.RECORD_BYTES)
				if bytes ~= seen.raws[at + record] then
					return false, `Run {run}'s frame record {record} of block {index} is not the one the client decoded`
				end
			end

			at += block.recordCount
			if buffer.len(part.data) > Constants.MAX_RELAY_BYTES then
				passed += 1
			end
		end
	end

	stop()

	if passed == 0 then
		return false, "No frame block of the expanded changes passed 896 B"
	end

	return true, nil
end
