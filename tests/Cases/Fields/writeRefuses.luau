--[[
    Fields.write refuses a value outside its declared range or width, of the
    wrong type, missing or past its list count, naming the list, the index
    of the first field that failed and its name
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local FIELDS: string = "src/Codec/Fields.luau"

type Row = { list: string, change: (values: { [string]: any }) -> (), text: string }

local ROWS: { Row } = {
	{
		list = "command",
		change = function (values: { [string]: any })
			values.slot = 8
		end,
		text = "fields.command field 1 (slot)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.slot = "seven"
		end,
		text = "field 1 (slot)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.reload = 1
		end,
		text = "field 2 (reload)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.uses = 10 -- Inside its 4 bits, past its declared 9
		end,
		text = "field 3 (uses)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			table.insert(values.shots, { sequence = 0, fraction = 0, yaw = 0, class = 0 })
		end,
		text = "field 4 (shots)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.shots[2].fraction = 101
		end,
		text = "field 6 (fraction)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.shots[1].class = 3
		end,
		text = "field 8 (class)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.shots[1] = 5
		end,
		text = "field 4 (shots)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.seed = 2 ^ 32
		end,
		text = "field 9 (seed)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.seed = nil
		end,
		text = "field 9 (seed)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.offset = 1.5
		end,
		text = "field 10 (offset)",
	},
	{
		list = "command",
		change = function (values: { [string]: any })
			values.fixed = 6
		end,
		text = "field 11 (fixed)",
	},
	{
		list = "slot",
		change = function (values: { [string]: any })
			values.badge = true
		end,
		text = "fields.slot field 4 (badge)",
	},
	{
		list = "slot",
		change = function (values: { [string]: any })
			values.badge.shiny = nil
		end,
		text = "fields.slot field 6 (shiny)",
	},
	{
		list = "rules",
		change = function (values: { [string]: any })
			values.flags = { true, true, true, true }
		end,
		text = "fields.rules field 3 (flags)",
	},
}

-- A copy of a fixture's values deep enough that a row's change reaches none of the fixture's tables
local function copy(values: any): any
	if type(values) ~= "table" then
		return values
	end

	local made: { [any]: any } = {}
	for key: any, value: any in values do
		made[key] = copy(value)
	end

	return made
end

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)
	local data: buffer = buffer.create(64)

	for index: number, row: Row in ROWS do
		local values: { [string]: any } = copy(Game.high[row.list])
		row.change(values)

		local refused: boolean, why: string = Refuses(row.text, Fields.write, layout[row.list], values, data, 0)
		if not refused then
			return false, `Value {index} ({row.text}) wasn't refused as it should be: {why}`
		end
	end

	return true, nil
end
