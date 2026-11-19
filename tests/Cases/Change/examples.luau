--[[
    A change record carries only what differs from its baseline, as the
    packets note's examples give it for slot 37 generation 2 in a block at
    relay tick 1000: a walk in 8 B, a still repeat in 4 B, a turn in 7 B
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLOT: number = 37
local GENERATION: number = 2
local BLOCK_TICK: number = 1000
local START: vector = vector.create(100, 10, -200)
local PITCH_STEP: number = (math.pi / 2) / 127 -- A record's i8 pitch step
local FILL: number = 0xEE -- What the bytes past a change hold, so a write past its length shows

type Example = { name: string, baselineTick: number, current: { [string]: any }, bytes: { number } }

local EXAMPLES: { Example } = {
	{
		name = "a walk of +1.5 studs X and -0.75 studs Z against tick 997",
		baselineTick = 997,
		current = { position = START + vector.create(1.5, 0, -0.75) },
		bytes = { 0x25, 0x20, 0x03, 0x03, 0x60, 0x00, 0xD0, 0xFF },
	},
	{
		name = "a still repeat against tick 980",
		baselineTick = 980,
		current = { position = START },
		bytes = { 0x25, 0x20, 0x14, 0x00 },
	},
	{
		name = "a turn in place to yaw 90° and pitch +10 steps against tick 997",
		baselineTick = 997,
		current = { position = START, yaw = math.pi / 2, pitch = 10 * PITCH_STEP },
		bytes = { 0x25, 0x20, 0x03, 0x18, 0x00, 0x40, 0x0A },
	},
}

-- Bytes as two hex digits each, space apart
local function hex(data: buffer, at: number, length: number): string
	local digits: { string } = {}
	for index: number = 0, length - 1 do
		table.insert(digits, string.format("%02X", buffer.readu8(data, at + index)))
	end

	return table.concat(digits, " ")
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Change: any = globals.require(tread.Codec.Change)
	local Record: any = globals.require(tread.Codec.Record)

	-- A record of slot 37 generation 2 with the fields given, the rest at rest
	local function encode(fields: { [string]: any }): buffer
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = SLOT, GENERATION
		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(16)
		Record.write(record, data, 0, Game.limits)

		return data
	end

	local baseline: buffer = encode({ position = START })

	for _, example: Example in EXAMPLES do
		local current: buffer = encode(example.current)
		local into: buffer = buffer.create(16)
		buffer.fill(into, 0, FILL)

		local base: number = BLOCK_TICK - example.baselineTick
		local length: number = Change.write(current, 0, baseline, 0, base, into, 0)
		local expected: buffer = buffer.create(#example.bytes)
		for index: number, byte: number in example.bytes do
			buffer.writeu8(expected, index - 1, byte)
		end

		if length ~= #example.bytes or hex(into, 0, length) ~= hex(expected, 0, #example.bytes) then
			local wrote: string = hex(into, 0, length)
			return false, `{example.name} wrote {wrote} ({length} B), not {hex(expected, 0, #example.bytes)}`
		elseif length < 16 and buffer.readu8(into, length) ~= FILL then
			return false, `{example.name} wrote past its {length} B`
		elseif Change.length(buffer.readu8(into, 3)) ~= length then
			return false, `{example.name}'s mask names {Change.length(buffer.readu8(into, 3))} B, not its {length}`
		end

		-- Read back against the same baseline, it is the current record byte for byte
		local rebuilt: buffer = buffer.create(16)
		local read: number = Change.read(into, 0, baseline, 0, rebuilt, 0)
		if read ~= length or buffer.tostring(rebuilt) ~= buffer.tostring(current) then
			return false, `{example.name} read back as {hex(rebuilt, 0, 16)}, not {hex(current, 0, 16)}`
		end
	end

	return true, nil
end
