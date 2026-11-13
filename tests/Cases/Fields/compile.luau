--[[
    Fields.compile packs each declaration in the fewest bits its range takes,
    counts each list's indices depth first, gives each list's largest bytes,
    and takes a list that fills its bound exactly
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local FIELDS: string = "src/Codec/Fields.luau"
local LISTS: { string } = { "command", "rules", "server", "slot", "held" }

-- Each command entry's index, width, count and count width, from the fixture's declarations
local COMMAND: { { any } } = {
	{ "slot", 1, 3, 0, 0 },
	{ "reload", 2, 1, 0, 0 },
	{ "uses", 3, 4, 0, 0 },
	{ "shots", 4, 0, 2, 2 },
	{ "seed", 9, 32, 0, 0 },
	{ "offset", 10, 32, 0, 0 },
	{ "fixed", 11, 0, 0, 0 },
}

-- The shots group's own entries: index, width and the low end each value packs above
local SHOT: { { any } } = {
	{ "sequence", 5, 8, 0 },
	{ "fraction", 6, 8, -100 },
	{ "yaw", 7, 16, 0 },
	{ "class", 8, 2, 0 },
}

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)

	for _, key: string in LISTS do
		local list: any = layout[key]
		if list.name ~= `fields.{key}` or list.bytes ~= Game.bytes[key] then
			return false, `{key} compiled as {list.name} of {list.bytes} B, where it fills {Game.bytes[key]} B`
		end
	end

	local command: any = layout.command
	if command.last ~= 11 or #command.entries ~= #COMMAND then
		return false, `The command list's last index is {command.last} over {#command.entries} entries`
	end

	for position: number, row: { any } in COMMAND do
		local entry: any = command.entries[position]
		if entry.name ~= row[1] or entry.index ~= row[2] or entry.width ~= row[3] then
			return false, `Command entry {position} compiled as {entry.name}, index {entry.index}, {entry.width} bits`
		elseif entry.count ~= row[4] or entry.countWidth ~= row[5] then
			return false, `{entry.name}'s list compiled as {entry.count} in {entry.countWidth} bits`
		end
	end

	local shots: any = command.entries[4]
	for position: number, row: { any } in SHOT do
		local entry: any = shots.fields[position]
		if entry.name ~= row[1] or entry.index ~= row[2] or entry.width ~= row[3] or entry.min ~= row[4] then
			return false, `Shot entry {position} compiled as {entry.name}, index {entry.index}, {entry.width} bits`
		end
	end

	if shots.kind ~= "dropped" or command.entries[1].kind ~= "held" or command.entries[2].kind ~= "carried" then
		return false, "The command entries lost the kinds they were declared with"
	elseif layout.rules.entries[2].start ~= -20 or layout.server.entries[1].start ~= false then
		return false, "The rule-state and server-set entries lost their starts"
	elseif layout.slot.entries[1].optional ~= true or layout.slot.entries[2].optional ~= false then
		return false, "The slot-table entries lost which are optional"
	end

	-- Each list filling exactly its bound compiles
	local largest: any = Fields.compile(Game.largest)
	local bounds: { [string]: number } = { command = 64, rules = 32, server = 16, slot = 64, held = 16 }
	for key: string, bound: number in bounds do
		if largest[key].bytes ~= bound then
			return false, `The largest {key} list compiled to {largest[key].bytes} B, where it fills its {bound} B`
		end
	end

	return true, nil
end
