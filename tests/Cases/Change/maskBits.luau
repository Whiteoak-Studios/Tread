--[[
    Each field that differs from the baseline sets its mask bit alone and
    fills its bytes, Y as a step out to an i8's edges and whole past them,
    and every change reads back to the current record at any offsets
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLOT: number = 600
local GENERATION: number = 9
local START: vector = vector.create(-300, 50, 400)
local STUD_STEP: number = 1 / 64 -- A record's X and Z step
local HEIGHT_STEP: number = 1 / 32 -- Its Y step

-- Where each buffer holds its record or change, none at 0, so an offset dropped anywhere shows
local CURRENT_AT: number = 7
local BASELINE_AT: number = 20
local CHANGE_AT: number = 3
local REBUILT_AT: number = 9

type Row = { name: string, fields: { [string]: any }, mask: number, length: number }

-- The baseline's fields; each row's fields stand in for the baseline's
local BASELINE: { [string]: any } = { position = START, yaw = 1, pitch = 0.2, word = 5, lean = 4 }

local ROWS: { Row } = {
	{ name = "X", fields = { position = START + vector.create(STUD_STEP, 0, 0) }, mask = 1, length = 6 },
	{ name = "Z", fields = { position = START - vector.create(0, 0, STUD_STEP) }, mask = 2, length = 6 },
	{ name = "a Y step", fields = { position = START + vector.create(0, HEIGHT_STEP, 0) }, mask = 4, length = 5 },
	{ name = "yaw", fields = { yaw = 2 }, mask = 8, length = 6 },
	{ name = "pitch", fields = { pitch = 0.3 }, mask = 16, length = 5 },
	{ name = "the state word", fields = { word = 6 }, mask = 32, length = 6 },
	{ name = "the last byte", fields = { lean = 5 }, mask = 64, length = 5 },
	{
		name = "a whole Y",
		fields = { position = START + vector.create(0, 200 * HEIGHT_STEP, 0) },
		mask = 128,
		length = 6,
	},

	-- Y's step reaches an i8's edges either way, and goes whole one step past each
	{
		name = "Y up 127 steps",
		fields = { position = START + vector.create(0, 127 * HEIGHT_STEP, 0) },
		mask = 4,
		length = 5,
	},
	{
		name = "Y up 128 steps",
		fields = { position = START + vector.create(0, 128 * HEIGHT_STEP, 0) },
		mask = 128,
		length = 6,
	},
	{
		name = "Y down 128 steps",
		fields = { position = START - vector.create(0, 128 * HEIGHT_STEP, 0) },
		mask = 4,
		length = 5,
	},
	{
		name = "Y down 129 steps",
		fields = { position = START - vector.create(0, 129 * HEIGHT_STEP, 0) },
		mask = 128,
		length = 6,
	},

	-- X and Z reach an i16's edges either way
	{
		name = "X up 32,767 steps",
		fields = { position = START + vector.create(32767 * STUD_STEP, 0, 0) },
		mask = 1,
		length = 6,
	},
	{
		name = "Z down 32,768 steps",
		fields = { position = START - vector.create(0, 0, 32768 * STUD_STEP) },
		mask = 2,
		length = 6,
	},
	{ name = "nothing", fields = {}, mask = 0, length = 4 },
}

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Change: any = globals.require(tread.Codec.Change)
	local Record: any = globals.require(tread.Codec.Record)

	-- A record of the baseline's fields with the given ones over them, at an offset of a buffer of its own
	local function encode(fields: { [string]: any }, base: { [string]: any }, at: number): buffer
		local record: { [string]: any } = Record.new()
		record.slot, record.generation = SLOT, GENERATION
		for name: string, value: any in base do
			record[name] = value
		end

		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(at + 16)
		Record.write(record, data, at, Game.limits)

		return data
	end

	local function check(name: string, current: buffer, baseline: buffer, mask: number, length: number): string?
		local into: buffer = buffer.create(CHANGE_AT + 16)
		local wrote: number = Change.write(current, CURRENT_AT, baseline, BASELINE_AT, 1, into, CHANGE_AT)

		if wrote ~= length or buffer.readu8(into, CHANGE_AT + 3) ~= mask then
			return `{name} wrote {wrote} B with mask {buffer.readu8(into, CHANGE_AT + 3)}, not {length} B with {mask}`
		elseif Change.length(mask) ~= length then
			return `Mask {mask} names {Change.length(mask)} B, not {length}`
		end

		local rebuilt: buffer = buffer.create(REBUILT_AT + 16)
		local read: number = Change.read(into, CHANGE_AT, baseline, BASELINE_AT, rebuilt, REBUILT_AT)
		if
			read ~= length
			or buffer.readstring(rebuilt, REBUILT_AT, 16) ~= buffer.readstring(current, CURRENT_AT, 16)
		then
			return `{name} read back as another record`
		end

		return nil
	end

	local baseline: buffer = encode({}, BASELINE, BASELINE_AT)

	for _, row: Row in ROWS do
		local differs: string? =
			check(row.name, encode(row.fields, BASELINE, CURRENT_AT), baseline, row.mask, row.length)
		if differs then
			return false, differs
		end
	end

	-- A rider's platform and the head offset's selector, the same on both, ride along in X's and Z's top bits
	local riding: { [string]: any } = { position = START, platform = 77, headYaw = 30, headPitch = -20 }
	local moved: { [string]: any } = { position = START + vector.create(5, 0, -5) }
	local differs: string? =
		check("a rider's move", encode(moved, riding, CURRENT_AT), encode({}, riding, BASELINE_AT), 3, 8)
	if differs then
		return false, differs
	end

	-- The lengths every mask names: the header alone, every field with a Y step, every one with a whole Y, and none
	-- for a mask holding Y both ways
	local lengths: { { number } } = { { 0, 4 }, { 0x7F, 15 }, { 0xFB, 16 }, { 0x84, 0 }, { 0xFF, 0 } }
	for _, pair: { number } in lengths do
		if Change.length(pair[1]) ~= pair[2] then
			return false, `Mask {pair[1]} names {Change.length(pair[1])} B, not {pair[2]}`
		end
	end

	return true, nil
end
