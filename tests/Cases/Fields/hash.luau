--[[
    Fields.hash is the 32-bit FNV-1a hash of the declarations a layout was
    compiled from: the same declarations give the same hash, and a change to
    any part of any declaration gives another
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local FIELDS: string = "src/Codec/Fields.luau"
local OFFSET: number = 2166136261
local PRIME: number = 16777619
local HALF_WORD: number = 2 ^ 16

-- FNV-1a with its multiply split over the hash's two 16-bit halves, apart from how the codec splits it
local function fnv(text: string): number
	local hash: number = OFFSET

	for position: number = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, position))

		local low: number = hash % HALF_WORD
		local high: number = hash // HALF_WORD
		hash = (low * PRIME + (high * PRIME % HALF_WORD) * HALF_WORD) % 2 ^ 32
	end

	return hash
end

local function empty(): { [string]: any }
	return { command = {}, rules = {}, server = {}, slot = {}, held = {} }
end

-- A deep copy of the fixture's declarations, which a change can reach without touching the fixture
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local made: { [any]: any } = {}
	for key: any, inner: any in value do
		made[key] = copy(inner)
	end

	return made
end

-- One change to a copy of the declarations each, every one of which must move the hash
local CHANGES: { (declarations: { [string]: any }) -> () } = {
	function (declarations: { [string]: any })
		declarations.command[1].name = "slots"
	end,
	function (declarations: { [string]: any })
		declarations.command[1].bits = 4
	end,
	function (declarations: { [string]: any })
		declarations.command[3].max = 8
	end,
	function (declarations: { [string]: any })
		declarations.command[1].kind = "dropped"
	end,
	function (declarations: { [string]: any })
		declarations.command[4].count = 3
	end,
	function (declarations: { [string]: any })
		declarations.command[4].fields[2].min = -99
	end,
	function (declarations: { [string]: any })
		declarations.rules[1].start = 1
	end,
	function (declarations: { [string]: any })
		declarations.slot[2].optional = true
	end,
	function (declarations: { [string]: any })
		declarations.held[1].type = "int"
	end,
	function (declarations: { [string]: any })
		table.insert(declarations.server, { name = "extra", type = "bool" })
	end,
	function (declarations: { [string]: any })
		local first: any = table.remove(declarations.rules, 1)
		table.insert(declarations.rules, first)
	end,
	function (declarations: { [string]: any })
		-- The same field moved to the server-set list from the rule-state one
		table.insert(declarations.server, table.remove(declarations.rules) :: any)
	end,
}

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)

	-- The oracle first: FNV-1a's published values
	if fnv("") ~= 0x811C9DC5 or fnv("a") ~= 0xE40C292C or fnv("foobar") ~= 0xBF9CF968 then
		return false, "The case's own FNV-1a gives other values than FNV-1a's published ones"
	end

	-- The text the hash runs over, for no declarations and for one
	local none: number = Fields.hash(Fields.compile(empty()))
	local noneText: string = "fields.command[]fields.rules[]fields.server[]fields.slot[]fields.held[]"
	if none ~= fnv(noneText) then
		return false, `No declarations hash to {none}, where FNV-1a of their text is {fnv(noneText)}`
	end

	local one: { [string]: any } = empty()
	one.command = { { name = "slot", type = "uint", bits = 3, kind = "held" } }
	local oneCommand: string = "fields.command[4:slot,uint,0,7,0,false,held,nil[]]"
	local oneText: string = `{oneCommand}fields.rules[]fields.server[]fields.slot[]fields.held[]`
	if Fields.hash(Fields.compile(one)) ~= fnv(oneText) then
		return false, "One declaration hashes to another value than FNV-1a of its text"
	end

	local base: number = Fields.hash(Fields.compile(Game.fields))
	if base ~= Fields.hash(Fields.compile(copy(Game.fields))) then
		return false, "The same declarations hashed to two values"
	elseif base % 1 ~= 0 or base < 0 or base >= 2 ^ 32 then
		return false, `The hash {base} is no 32-bit whole number`
	end

	local seen: { [number]: number } = { [base] = 0 }
	for index: number, change: (declarations: { [string]: any }) -> () in CHANGES do
		local declarations: { [string]: any } = copy(Game.fields)
		change(declarations)

		local hash: number = Fields.hash(Fields.compile(declarations))
		if seen[hash] then
			return false, `Change {index} hashed to {hash}, as change {seen[hash]} did, where it must differ`
		end

		seen[hash] = index
	end

	return true, nil
end
