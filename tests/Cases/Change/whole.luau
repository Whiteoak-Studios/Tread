--[[
    A record goes whole, Change.write giving 0 and writing nothing, against a
    baseline of another life, at a base outside 1 to 31, and when X or Z
    moved past an i16's difference or the platform or selector bits changed
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLOT: number = 37
local GENERATION: number = 2
local START: vector = vector.create(-300, 10, 400)
local STUD_STEP: number = 1 / 64
local FILL: number = 0xEE

type Row = { name: string, fields: { [string]: any }, base: number }

local ROWS: { Row } = {
	{ name = "another slot", fields = { slot = SLOT + 1 }, base = 1 },
	{ name = "another generation", fields = { generation = GENERATION + 1 }, base = 1 },
	{ name = "a base of 0", fields = {}, base = 0 },
	{ name = "a base of 32", fields = {}, base = 32 },
	{ name = "X up 512 studs", fields = { position = START + vector.create(32768 * STUD_STEP, 0, 0) }, base = 1 },
	{ name = "X down 32,769 steps", fields = { position = START - vector.create(32769 * STUD_STEP, 0, 0) }, base = 1 },
	{ name = "Z up 600 studs", fields = { position = START + vector.create(0, 0, 600) }, base = 1 },
	{ name = "a platform boarded", fields = { platform = 1 }, base = 1 },
	{ name = "the head offset set", fields = { headYaw = 10 }, base = 1 },
}

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Change: any = globals.require(tread.Codec.Change)
	local Record: any = globals.require(tread.Codec.Record)

	local function encode(fields: { [string]: any }): buffer
		local record: { [string]: any } = Record.new()
		record.slot, record.generation, record.position = SLOT, GENERATION, START
		for name: string, value: any in fields do
			record[name] = value
		end

		local data: buffer = buffer.create(16)
		Record.write(record, data, 0, Game.limits)

		return data
	end

	local baseline: buffer = encode({})
	local untouched: buffer = buffer.create(16)
	buffer.fill(untouched, 0, FILL)

	for _, row: Row in ROWS do
		local into: buffer = buffer.create(16)
		buffer.fill(into, 0, FILL)

		local length: number = Change.write(encode(row.fields), 0, baseline, 0, row.base, into, 0)
		if length ~= 0 then
			return false, `{row.name} went as a change of {length} B, not whole`
		elseif buffer.tostring(into) ~= buffer.tostring(untouched) then
			return false, `{row.name} went whole but wrote into the change's bytes`
		end
	end

	-- Bases of 1 and 31 are the edges a change still takes
	for _, base: number in { 1, 31 } do
		if Change.write(encode({}), 0, baseline, 0, base, buffer.create(16), 0) ~= 4 then
			return false, `A still record at a base of {base} went whole`
		end
	end

	return true, nil
end
