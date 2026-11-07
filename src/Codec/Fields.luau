--[[
    The game's declared fields: the declarations checked and compiled into
    the layout each block of game fields packs against, their hash, and a
    table of values by name packed to and from its bytes
--]]

--!strict
--!native
local Bits = require(script.Parent.Bits)
local Constants = require(script.Parent.Parent.Constants)
local Hash = require(script.Parent.Hash)
local State = require(script.Parent.Parent.Step.State)

local BYTE_BITS: number = 8
local MAX_BITS: number = 32 -- A number field's widest, what one bit32 write holds

-- The keys a declaration may hold
local KEYS: { [string]: boolean } = {
	name = true,
	type = true,
	bits = true,
	min = true,
	max = true,
	count = true,
	kind = true,
	start = true,
	fields = true,
	optional = true,
}

local TYPES: { [string]: boolean } = { uint = true, int = true, bool = true, group = true }
local KINDS: { [string]: boolean } = { held = true, carried = true, dropped = true }

type Field = State.Field
type Values = State.Values

-- What one declaration list allows, and the most its packing may fill
type Rules = {
	key: string,
	bound: number,
	kinds: boolean, -- Each of its own fields needs a kind
	starts: boolean, -- Its fields may give a start
	optionals: boolean, -- Its fields may be optional
}

-- One declaration compiled: how its value packs, and what it declared
export type Entry = {
	name: string,
	index: number, -- Its place among its list's declarations, depth first from 1, which a refusal names
	type: "uint" | "int" | "bool" | "group",
	width: number, -- The bits one value packs into, the fewest that hold its range
	min: number, -- A number packs as its distance above this
	max: number,
	count: number, -- The most a list holds, 0 for a single value
	countWidth: number, -- The bits a list's length packs into
	optional: boolean, -- Packed behind a presence bit
	kind: ("held" | "carried" | "dropped")?, -- A command field's
	start: (number | boolean)?,
	fields: { Entry }, -- A group's own, empty for any other
}

-- One declaration list compiled
export type List = {
	name: string, -- Which list it is, as a refusal names it
	entries: { Entry },
	bytes: number, -- The most bytes its packing fills
	last: number, -- The highest index among its declarations
}

-- The game's five declaration lists compiled, which every block of game fields packs against
export type Layout = {
	command: List,
	rules: List,
	server: List,
	slot: List,
	held: List,
}

local COMMAND: Rules = {
	key = "command",
	bound = Constants.MAX_COMMAND_FIELDS,
	kinds = true,
	starts = false,
	optionals = false,
}

local RULE_STATE: Rules = {
	key = "rules",
	bound = Constants.MAX_RULE_STATE,
	kinds = false,
	starts = true,
	optionals = false,
}

local SERVER_SET: Rules = {
	key = "server",
	bound = Constants.MAX_SERVER_SET,
	kinds = false,
	starts = true,
	optionals = false,
}

local SLOT_TABLE: Rules = {
	key = "slot",
	bound = Constants.MAX_LOOK,
	kinds = false,
	starts = false,
	optionals = true,
}

local HELD_ITEM: Rules = {
	key = "held",
	bound = Constants.MAX_HELD,
	kinds = false,
	starts = false,
	optionals = true,
}

-- One writer and one reader every packing aims again, so none makes a table
local Writer: Bits.Cursor = Bits.writer(buffer.create(0), 0, 0)
local Reader: Bits.Cursor = Bits.reader(buffer.create(0), 0, 0)

local Fields = {}

local function refuse(path: string, problem: string): never
	error(`{path} {problem}`)
end

-- The fewest bits that hold every whole number from 0 to range
local function widthOf(range: number): number
	local width: number = 0

	while 2 ^ width <= range do
		width += 1
	end

	return width
end

local function whole(value: any): boolean
	return type(value) == "number" and value % 1 == 0
end

-- The most bits one entry's packing fills
local function largest(entry: Entry): number
	local one: number = entry.width

	if entry.type == "group" then
		for _, inner: Entry in entry.fields do
			one += largest(inner)
		end
	end

	local bits: number = entry.count > 0 and entry.countWidth + entry.count * one or one

	return entry.optional and bits + 1 or bits
end

local compileEntries: (fields: any, rules: Rules, path: string, top: boolean, index: number) -> ({ Entry }, number)

--[[
    Checks one declaration against what its list allows and compiles it,
    erroring on the first thing wrong with it, and gives the index the next
    declaration takes
--]]

local function compileEntry(field: any, rules: Rules, path: string, top: boolean, index: number): (Entry, number)
	if type(field) ~= "table" then
		refuse(path, "is no declaration table")
	end

	for key: any in field do
		if not KEYS[key] then
			refuse(path, `holds {key}, which no declaration takes`)
		end
	end

	local name: any = field.name
	local fieldType: any = field.type
	if type(name) ~= "string" or name == "" then
		refuse(path, "needs a name")
	elseif not TYPES[fieldType] then
		refuse(path, `({name}) needs a type of uint, int, bool or group`)
	end

	path = `{path} ({name})`

	-- A number packs as its distance above min, in the fewest bits that hold its range
	local min: number = 0
	local max: number = 1
	local width: number = 1

	if fieldType == "uint" or fieldType == "int" then
		local bits: any = field.bits
		if not whole(bits) or bits < 1 or bits > MAX_BITS then
			refuse(path, `needs bits, a whole number from 1 to {MAX_BITS}`)
		end

		local low: number = fieldType == "int" and -2 ^ (bits - 1) or 0
		local high: number = low + 2 ^ bits - 1

		if field.min ~= nil then
			min = field.min
		else
			min = low
		end

		if field.max ~= nil then
			max = field.max
		else
			max = high
		end

		if not (whole(min) and whole(max) and low <= min and min <= max and max <= high) then
			refuse(path, `needs min and max whole, in order and inside {low} to {high}, the range its bits hold`)
		end

		width = widthOf(max - min)
	elseif field.bits ~= nil or field.min ~= nil or field.max ~= nil then
		refuse(path, `is a {fieldType}, which takes no bits, min or max`)
	elseif fieldType == "group" then
		width = 0
	end

	local count: any = field.count
	local countWidth: number = 0
	if count ~= nil then
		if not whole(count) or count < 1 then
			refuse(path, "needs a count, a whole number from 1")
		end

		countWidth = widthOf(count)
	end

	local optional: any = field.optional
	if optional ~= nil and type(optional) ~= "boolean" then
		refuse(path, "needs optional true or false")
	elseif optional and not rules.optionals then
		refuse(path, "is optional, which only a slot-table or held-item field may be")
	end

	local kind: any = field.kind
	if top and rules.kinds then
		if not KINDS[kind] then
			refuse(path, "needs a kind of held, carried or dropped")
		elseif kind == "carried" and ((fieldType ~= "bool" and fieldType ~= "uint") or count ~= nil) then
			refuse(path, "is carried, so it must be one bool or one uint, which a carry merges")
		end
	elseif kind ~= nil then
		refuse(path, "holds a kind, which only a command field takes")
	end

	local start: any = field.start
	if start ~= nil then
		if not rules.starts then
			refuse(path, "holds a start, which only a rule-state or server-set field takes")
		elseif fieldType == "group" or count ~= nil then
			refuse(path, "holds a start, which a group or a list takes none of")
		elseif fieldType == "bool" and type(start) ~= "boolean" then
			refuse(path, "needs a start of true or false")
		elseif fieldType ~= "bool" and not (whole(start) and min <= start and start <= max) then
			refuse(path, `needs a start whole and inside {min} to {max}`)
		end
	end

	local entries: { Entry } = {}
	local after: number = index + 1
	if fieldType == "group" then
		if type(field.fields) ~= "table" or #field.fields == 0 then
			refuse(path, "is a group, so it needs fields, a list of at least one declaration")
		end

		entries, after = compileEntries(field.fields, rules, `{path}.fields`, false, index + 1)
	elseif field.fields ~= nil then
		refuse(path, `is a {fieldType}, which holds no fields`)
	end

	local entry: Entry = {
		name = name,
		index = index,
		type = fieldType,
		width = width,
		min = min,
		max = max,
		count = count or 0,
		countWidth = countWidth,
		optional = optional == true,
		kind = kind,
		start = start,
		fields = entries,
	}

	return entry, after
end

--[[
    Compiles a list of sibling declarations in order, refusing a name two
    of them share, and gives the index the next declaration takes
--]]

function compileEntries(fields: any, rules: Rules, path: string, top: boolean, index: number): ({ Entry }, number)
	local entries: { Entry } = {}
	local names: { [string]: boolean } = {}

	for position: number = 1, #fields do
		local entry: Entry
		entry, index = compileEntry(fields[position], rules, `{path}[{position}]`, top, index)

		if names[entry.name] then
			refuse(`{path}[{position}]`, `reuses the name {entry.name}`)
		end

		names[entry.name] = true
		entries[position] = entry
	end

	return entries, index
end

local function compileList(fields: any, rules: Rules): List
	local path: string = `fields.{rules.key}`
	if type(fields) ~= "table" then
		refuse(path, "is no list of declarations")
	end

	local entries: { Entry }, after: number = compileEntries(fields, rules, path, true, 1)

	local bits: number = 0
	for _, entry: Entry in entries do
		bits += largest(entry)
	end

	local bytes: number = math.ceil(bits / BYTE_BITS)
	if bytes > rules.bound then
		refuse(path, `can fill {bytes} B at its largest, past the {rules.bound} B it may`)
	end

	return { name = path, entries = entries, bytes = bytes, last = after - 1 }
end

--[[
    Checks the game's five declaration lists and compiles each, erroring on
    the first declaration that is wrong, naming it, and on the first list
    whose largest packing passes its bound, naming the list
--]]

function Fields.compile(declarations: State.Fields): Layout
	if type(declarations) ~= "table" then
		error("fields is no table of the five declaration lists")
	end

	return {
		command = compileList(declarations.command, COMMAND),
		rules = compileList(declarations.rules, RULE_STATE),
		server = compileList(declarations.server, SERVER_SET),
		slot = compileList(declarations.slot, SLOT_TABLE),
		held = compileList(declarations.held, HELD_ITEM),
	}
end

-- Appends each entry's declaration to the text the hash runs over, every part in a fixed order
local function describe(entries: { Entry }, parts: { string })
	for _, entry: Entry in entries do
		local declared: string = `{entry.type},{entry.min},{entry.max},{entry.count},{entry.optional}`
		table.insert(parts, `{#entry.name}:{entry.name},{declared},{entry.kind},{entry.start}[`)
		describe(entry.fields, parts)
		table.insert(parts, "]")
	end
end

--[[
    The 32-bit FNV-1a hash of the declarations a layout was compiled from,
    which a keyframe carries beside CODEC_VERSION, so a recording names the
    declarations its bytes were packed with
--]]

function Fields.hash(layout: Layout): number
	local parts: { string } = {}
	for _, list: List in { layout.command, layout.rules, layout.server, layout.slot, layout.held } do
		table.insert(parts, `{list.name}[`)
		describe(list.entries, parts)
		table.insert(parts, "]")
	end

	return Hash.text(table.concat(parts))
end

local function refuseValue(list: List, entry: Entry, value: any): never
	error(`{list.name} field {entry.index} ({entry.name}) can't pack {value}, which its declaration doesn't hold`)
end

local writeEntry: (list: List, entry: Entry, value: any) -> ()

-- Packs one value of an entry, a list's element or the whole of a single one
local function writeValue(list: List, entry: Entry, value: any)
	local entryType: string = entry.type

	if entryType == "group" then
		if type(value) ~= "table" then
			refuseValue(list, entry, value)
		end

		for _, inner: Entry in entry.fields do
			writeEntry(list, inner, value[inner.name])
		end
	elseif entryType == "bool" then
		if type(value) ~= "boolean" then
			refuseValue(list, entry, value)
		end

		Bits.write(Writer, value and 1 or 0, 1)
	else
		if not (type(value) == "number" and value % 1 == 0 and value >= entry.min and value <= entry.max) then
			refuseValue(list, entry, value)
		end

		Bits.write(Writer, value - entry.min, entry.width)
	end
end

function writeEntry(list: List, entry: Entry, value: any)
	if entry.optional then
		Bits.write(Writer, value ~= nil and 1 or 0, 1)

		if value == nil then
			return
		end
	end

	if entry.count == 0 then
		writeValue(list, entry, value)

		return
	end

	if not (type(value) == "table" and #value <= entry.count) then
		refuseValue(list, entry, value)
	end

	Bits.write(Writer, #value, entry.countWidth)

	for position: number = 1, #value do
		writeValue(list, entry, value[position])
	end
end

--[[
    Packs values, a table of the list's fields by name, into data from
    offset, and gives the bytes it filled. It errors naming the index of the
    first field whose value its declaration doesn't hold, and on a buffer
    without room from offset for the list's largest packing
--]]

function Fields.write(list: List, values: Values, data: buffer, offset: number): number
	Bits.writer(data, offset, list.bytes, Writer)

	for _, entry: Entry in list.entries do
		writeEntry(list, entry, values[entry.name])
	end

	return Bits.bytes(Writer)
end

local readEntry: (entry: Entry, into: Values) -> number?

--[[
    Reads one value of an entry, a group into existing when that is already
    a table, and gives it, or nil and the entry's index when it runs past
    the bytes or outside its range
--]]

local function readValue(entry: Entry, existing: any): (any, number?)
	local entryType: string = entry.type

	if entryType == "group" then
		local group: Values = existing
		if type(existing) ~= "table" then
			group = {}
		end

		for _, inner: Entry in entry.fields do
			local failed: number? = readEntry(inner, group)
			if failed then
				return nil, failed
			end
		end

		return group, nil
	end

	local raw: number? = Bits.read(Reader, entry.width)
	if raw == nil or raw + entry.min > entry.max then
		return nil, entry.index
	elseif entryType == "bool" then
		return raw == 1, nil
	end

	return raw + entry.min, nil
end

function readEntry(entry: Entry, into: Values): number?
	local name: string = entry.name

	if entry.optional then
		local present: number? = Bits.read(Reader, 1)
		if present == nil then
			return entry.index
		elseif present == 0 then
			into[name] = nil

			return nil
		end
	end

	if entry.count == 0 then
		local value: any, failed: number? = readValue(entry, into[name])
		if failed then
			return failed
		end

		into[name] = value

		return nil
	end

	local length: number? = Bits.read(Reader, entry.countWidth)
	if length == nil or length > entry.count then
		return entry.index
	end

	local list: { any } = into[name]
	if type(list) ~= "table" then
		list = {}
		into[name] = list
	end

	for position: number = 1, length do
		local value: any, failed: number? = readValue(entry, list[position])
		if failed then
			return failed
		end

		list[position] = value
	end

	-- A list shorter than the one it reuses loses its tail
	for position: number = #list, length + 1, -1 do
		list[position] = nil
	end

	return nil
end

--[[
    Unpacks the length bytes of data from offset into into, by name, a
    nested group or list into the table already there, and gives nil. When
    the bytes don't hold the list it gives the index of the first field that
    failed: a value outside its range, a list past its count or bytes that
    run out, or one past the last field's when bytes are left over or the
    padding isn't 0. into is left part written then
--]]

function Fields.read(list: List, data: buffer, offset: number, length: number, into: Values): number?
	if not (offset >= 0 and length >= 0 and offset + length <= buffer.len(data)) then
		error(`{list.name}: {length} B from byte {offset} pass the end of a {buffer.len(data)} B buffer`)
	elseif length > list.bytes then
		return list.last + 1
	end

	Bits.reader(data, offset, length, Reader)

	for _, entry: Entry in list.entries do
		local failed: number? = readEntry(entry, into)
		if failed then
			return failed
		end
	end

	-- What is left is the padding to a whole byte, and it is 0, so a set of values has one packing only
	local left: number = Reader.bits - Reader.bit
	if left >= BYTE_BITS or Bits.read(Reader, left) ~= 0 then
		return list.last + 1
	end

	return nil
end

return Fields
