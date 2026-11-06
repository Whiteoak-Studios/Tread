--[[
    A wire command whose game fields don't hold their declarations reads as
    refused at the index of the first field that failed, and a command whose
    game value its declaration doesn't hold is refused on write
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local COMMAND: string = "src/Codec/Command.luau"
local FIELDS: string = "src/Codec/Fields.luau"

return function (): (boolean, string | nil)
	local Command: any = Environment.load(COMMAND)
	local Fields: any = Environment.load(FIELDS)
	local layout: any = Fields.compile(Game.fields)

	local command: { [string]: any } = Command.new()
	command.fields = Game.high.command

	local wire: { [string]: any } = Command.wire()
	Command.write(command, wire, layout, Game.limits)

	-- The first shot's class sits at bit 42, in byte 5's bits 2 and 3, and 3 is past its declared 2
	local fields: buffer = wire.fields
	buffer.writeu8(fields, 5, bit32.replace(buffer.readu8(fields, 5), 3, 2, 2))
	if Command.read(wire, Command.new(), layout, Game.limits) ~= 8 then
		return false, "A class past its declared 2 wasn't refused at its index, 8"
	end

	-- The highest values a byte short run out in offset, the tenth field, and a byte over fail one past the last
	Command.write(command, wire, layout, Game.limits)
	local high: buffer = wire.fields

	wire.fields = buffer.create(Game.bytes.command - 1)
	buffer.copy(wire.fields, 0, high, 0, Game.bytes.command - 1)
	if Command.read(wire, Command.new(), layout, Game.limits) ~= 10 then
		return false, "Game fields a byte short weren't refused where they ran out, at 10"
	end

	wire.fields = buffer.create(Game.bytes.command + 1)
	buffer.copy(wire.fields, 0, high, 0, Game.bytes.command)
	if Command.read(wire, Command.new(), layout, Game.limits) ~= 12 then
		return false, "Game fields a byte over weren't refused one past the last field, at 12"
	end

	-- No bytes at all for a game that declares command fields
	wire.fields = buffer.create(0)
	if Command.read(wire, Command.new(), layout, Game.limits) ~= 1 then
		return false, "Empty game fields weren't refused at the first field, 1"
	end

	command.fields = table.clone(Game.high.command)
	command.fields.slot = 8
	local refused: boolean, why: string =
		Refuses("fields.command field 1 (slot)", Command.write, command, Command.wire(), layout, Game.limits)
	if not refused then
		return false, `A slot past its 3 bits was written: {why}`
	end

	return true, nil
end
