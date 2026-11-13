--[[
    S10's probe counts a target's withheld bytes a second from its withheld
    tap frames, each block's bytes and 3 B of framing, grouped by relay tick
    across the u16 wrap into whole seconds, the unfinished newest left out
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local RATE: number = 4 -- Relay ticks a second, the stand-in's
local REASON: string = "Hidden" -- Every withheld record's send reason

-- Each frame's relay tick and the records of each block it carries. Tick 2's frame is missing, so a grouping by the
-- frames' places rather than their ticks would put tick 6 in the second second
local FRAMES: { { any } } = {
	{ 65534, { 1 } }, -- 9 + 16 + 3 = 28 B
	{ 65535, {} },
	{ 0, { 2, 0 } }, -- 44 + 12
	{ 1, { 3 } }, -- 60, so the first second holds 144 B
	{ 3, { 1, 1 } }, -- 28 + 28
	{ 4, { 4 } }, -- 76
	{ 5, {} }, -- So the second second holds 132 B, whole once tick 5 is in
	{ 6, { 5 } }, -- 92, in the third second, which tick 7 leaves unfinished
	{ 7, {} },
}

local FIRST: { number } = { 144 } -- Through tick 4, the second second short of its last tick
local BOTH: { number } = { 144, 132 } -- Through tick 5, and through tick 7 with the third unfinished

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local Block: any = loaded.require(tread.Codec.Block)
	local Constants: any = loaded.require(tread.Constants)
	local Record: any = loaded.require(tread.Codec.Record)
	local Tap: any = loaded.require(tread.Codec.Tap)
	local Spectators: any = loaded.require(dataModel:GetService("ServerScriptService").Server.Spectators)

	-- A withheld block of that many whole records, each of its own slot, in a buffer of its exact length
	local function block(records: number): (buffer, { string })
		local pool: buffer = buffer.create(math.max(records, 1) * Constants.RECORD_BYTES)
		local made: any = Block.new()
		local reasons: { string } = {}

		for index: number = 1, records do
			local record: any = Record.new()
			record.slot, record.generation = index, 1
			Record.write(record, pool, (index - 1) * Constants.RECORD_BYTES, { lean = 1, headCone = 1 })

			made.records[index] = (index - 1) * Constants.RECORD_BYTES
			reasons[index] = REASON
		end

		made.recordData, made.recordCount = pool, records

		local scratch: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(made, scratch)
		local data: buffer = buffer.create(bytes)
		buffer.copy(data, 0, scratch, 0, bytes)

		return data, reasons
	end

	-- A tap frame at a relay tick carrying one withheld block for each record count given
	local function frame(tick: number, counts: { number }): buffer
		local body: buffer = buffer.create(Constants.TAP_BLOCK_BYTES) -- Room for every block here and more
		local filled: number = 0

		for _, records: number in counts do
			local data: buffer, reasons: { string } = block(records)
			filled = Tap.writeBlock(body, filled, data, reasons, records)
		end

		return Tap.frame(tick, #counts, body, filled, nil, 0, 0)
	end

	local frames: { buffer } = {}
	for _, spec: { any } in FRAMES do
		table.insert(frames, frame(spec[1], spec[2]))
	end

	-- 1) The seconds each run of frames gives, by tick across the wrap, a second counted once its last tick is in
	local runs: { { any } } = {
		{ 6, FIRST },
		{ 7, BOTH },
		{ #FRAMES, BOTH },
		{ 0, {} },
	}

	for _, run: { any } in runs do
		local count: number, wanted: { number } = run[1], run[2]
		local seconds: { number } = Spectators.withheld(table.move(frames, 1, count, 1, {}), RATE)

		if table.concat(seconds, ",") ~= table.concat(wanted, ",") then
			local got: string = table.concat(seconds, ",")
			return false, `The first {count} frames gave withheld seconds of {got} B, not {table.concat(wanted, ",")}`
		end
	end

	return true, nil
end
