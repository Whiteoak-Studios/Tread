--[[
    Every list packs its values at each field's lowest and highest and reads
    them back, from any offset, filling its largest bytes when full, and a
    read reuses the nested tables already there and drops what is absent
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Same = require("../../Fixtures/Codec/Same")

local FIELDS: string = "src/Codec/Fields.luau"
local LISTS: { string } = { "command", "rules", "server", "slot", "held" }
local OFFSET: number = 5 -- Where in the buffer each packing starts, past bytes it must leave alone
local GUARD: number = 170 -- What those bytes hold

return function (): (boolean, string | nil)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)
	local data: buffer = buffer.create(OFFSET + 64)

	for _, key: string in LISTS do
		for _, edge: string in { "low", "high" } do
			local values: { [string]: any } = (Game :: any)[edge][key]
			buffer.fill(data, 0, GUARD)

			local bytes: number = Fields.write(layout[key], values, data, OFFSET)
			if edge == "high" and bytes ~= Game.bytes[key] then
				return false,
					`{key}'s highest values filled {bytes} B, where its largest packing fills {Game.bytes[key]}`
			elseif buffer.readu8(data, OFFSET - 1) ~= GUARD then
				return false, `Packing {key} wrote before its offset`
			end

			local into: { [string]: any } = {}
			local failed: number? = Fields.read(layout[key], data, OFFSET, bytes, into)
			if failed then
				return false, `{key}'s {edge} values packed to bytes its read refused at field {failed}`
			end

			local differs: string? = Same(values, into, `{key}.{edge}`)
			if differs then
				return false, differs
			end
		end
	end

	-- A mid value in every field, each a quantum's step inside an edge
	local mid: { [string]: any } = {
		slot = 6,
		reload = false,
		uses = 8,
		shots = { { sequence = 1, fraction = -99, yaw = 65534, class = 1 } },
		seed = 2 ^ 32 - 2,
		offset = -2 ^ 31 + 1,
		fixed = 7,
	}
	local bytes: number = Fields.write(layout.command, mid, data, 0)
	local into: { [string]: any } = {}
	if Fields.read(layout.command, data, 0, bytes, into) ~= nil then
		return false, "The command's mid values packed to bytes its read refused"
	end

	local differs: string? = Same(mid, into, "command.mid")
	if differs then
		return false, differs
	end

	-- A read reuses the nested tables it finds, and empties a list and drops an optional the bytes don't hold
	local look: { [string]: any } = {}
	bytes = Fields.write(layout.slot, Game.high.slot, data, 0)
	Fields.read(layout.slot, data, 0, bytes, look)

	local colors: { number } = look.colors
	local badge: { [string]: any } = look.badge
	Fields.read(layout.slot, data, 0, bytes, look)
	if look.colors ~= colors or look.badge ~= badge then
		return false, "A second read made new tables where it found them already there"
	end

	bytes = Fields.write(layout.slot, Game.low.slot, data, 0)
	Fields.read(layout.slot, data, 0, bytes, look)
	if look.colors ~= colors or #colors ~= 0 or look.head ~= nil or look.badge ~= nil then
		return false, "A read of fewer values kept a list's tail or an absent optional"
	end

	-- A packing needs room for its largest from its offset
	local refused: boolean, why: string =
		Refuses("passes the end", Fields.write, layout.command, Game.low.command, buffer.create(17), 0)
	if not refused then
		return false, `A buffer without room for the command's largest packing wasn't refused: {why}`
	end

	return true, nil
end
