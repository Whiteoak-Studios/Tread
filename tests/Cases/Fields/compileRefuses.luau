--[[
    Fields.compile refuses each bad declaration naming it, and each list one
    bit past its bound naming the list: 64 B a command, 32 B of rule state,
    16 B server-set, 64 B of look and 16 B of held item
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local FIELDS: string = "src/Codec/Fields.luau"

type Row = { list: string, fields: any, text: string }

-- The five lists, empty but for one
local function only(list: string, fields: any): { [string]: any }
	local declarations: { [string]: any } = { command = {}, rules = {}, server = {}, slot = {}, held = {} }
	declarations[list] = fields

	return declarations
end

local function uint(extra: { [string]: any }): { [string]: any }
	local field: { [string]: any } = { name = "value", type = "uint", bits = 8 }
	for key: string, value: any in extra do
		field[key] = value
	end

	return field
end

local ROWS: { Row } = {
	{ list = "rules", fields = { 5 }, text = "fields.rules[1] is no declaration table" },
	{ list = "rules", fields = { uint({ colour = 1 }) }, text = "holds colour" },
	{ list = "rules", fields = { { type = "bool" } }, text = "fields.rules[1] needs a name" },
	{ list = "rules", fields = { { name = "", type = "bool" } }, text = "needs a name" },
	{ list = "rules", fields = { { name = "a", type = "float" } }, text = "(a) needs a type" },
	{ list = "rules", fields = { { name = "a", type = "uint" } }, text = "needs bits" },
	{ list = "rules", fields = { uint({ bits = 0 }) }, text = "needs bits" },
	{ list = "rules", fields = { uint({ bits = 33 }) }, text = "needs bits" },
	{ list = "rules", fields = { uint({ bits = 1.5 }) }, text = "needs bits" },
	{ list = "rules", fields = { uint({ min = 5, max = 4 }) }, text = "needs min and max" },
	{ list = "rules", fields = { uint({ max = 256 }) }, text = "needs min and max" },
	{ list = "rules", fields = { uint({ min = -1 }) }, text = "needs min and max" },
	{ list = "rules", fields = { uint({ min = 0.5 }) }, text = "needs min and max" },
	{ list = "rules", fields = { uint({ type = "int", min = -129 }) }, text = "needs min and max" },
	{ list = "rules", fields = { { name = "a", type = "bool", bits = 1 } }, text = "takes no bits" },
	{ list = "rules", fields = { { name = "a", type = "bool", max = 1 } }, text = "takes no bits" },
	{ list = "rules", fields = { uint({ count = 0 }) }, text = "needs a count" },
	{ list = "rules", fields = { uint({ count = 1.5 }) }, text = "needs a count" },
	{ list = "slot", fields = { uint({ optional = "yes" }) }, text = "needs optional true or false" },
	{ list = "rules", fields = { uint({ optional = true }) }, text = "is optional, which only" },
	{ list = "command", fields = { uint({ kind = "held", optional = true }) }, text = "is optional, which only" },
	{ list = "command", fields = { uint({}) }, text = "fields.command[1] (value) needs a kind" },
	{ list = "command", fields = { uint({ kind = "sometimes" }) }, text = "needs a kind" },
	{ list = "command", fields = { uint({ type = "int", kind = "carried" }) }, text = "is carried" },
	{ list = "command", fields = { uint({ kind = "carried", count = 2 }) }, text = "is carried" },
	{ list = "rules", fields = { uint({ kind = "held" }) }, text = "holds a kind" },
	{
		list = "command",
		fields = { { name = "shot", type = "group", kind = "dropped", fields = { uint({ kind = "held" }) } } },
		text = "fields.command[1] (shot).fields[1] (value) holds a kind",
	},
	{ list = "command", fields = { uint({ kind = "held", start = 0 }) }, text = "holds a start" },
	{ list = "slot", fields = { uint({ start = 0 }) }, text = "holds a start" },
	{ list = "rules", fields = { uint({ start = 256 }) }, text = "needs a start whole" },
	{ list = "rules", fields = { uint({ start = true }) }, text = "needs a start whole" },
	{ list = "rules", fields = { { name = "a", type = "bool", start = 0 } }, text = "start of true or false" },
	{ list = "rules", fields = { uint({ count = 2, start = 0 }) }, text = "a group or a list takes none of" },
	{ list = "rules", fields = { { name = "a", type = "group" } }, text = "needs fields" },
	{ list = "rules", fields = { { name = "a", type = "group", fields = {} } }, text = "needs fields" },
	{ list = "rules", fields = { uint({ fields = { uint({}) } }) }, text = "holds no fields" },
	{ list = "rules", fields = { uint({}), uint({}) }, text = "fields.rules[2] reuses the name value" },
	{
		list = "slot",
		fields = { { name = "a", type = "group", fields = { uint({}), uint({}) } } },
		text = "fields.slot[1] (a).fields[2] reuses the name value",
	},
	{ list = "held", fields = 5, text = "fields.held is no list of declarations" },
}

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)

	for index: number, row: Row in ROWS do
		local refused: boolean, why: string = Refuses(row.text, Fields.compile, only(row.list, row.fields))
		if not refused then
			return false, `Declaration {index} ({row.text}) wasn't refused as it should be: {why}`
		end
	end

	local refused: boolean, why: string = Refuses("fields is no table", Fields.compile, 5)
	if not refused then
		return false, `A fields that is no table wasn't refused: {why}`
	end

	-- One bit past each bound, named by its list and the bytes it can fill
	local past: { [string]: number } = { command = 65, rules = 33, server = 17, slot = 65, held = 17 }
	for list: string, bytes: number in past do
		local fields: { any } = table.clone(Game.largest[list])
		local extra: { [string]: any } = { name = "extra", type = "bool" }
		if list == "command" then
			extra.kind = "held"
		end

		table.insert(fields, extra)

		refused, why = Refuses(`fields.{list} can fill {bytes} B`, Fields.compile, only(list, fields))
		if not refused then
			return false, `{list} one bit past its bound wasn't refused: {why}`
		end
	end

	return true, nil
end
