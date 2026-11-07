--[[
    A Move whose one command fails its game fields is refused whole, its
    acknowledgments included, with the index of the first field that
    failed, and an encode of more than 8 commands or of commands out of
    order is refused
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local COMMAND: string = "src/Codec/Command.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local MOVE: string = "src/Codec/Move.luau"

return function (): (boolean, string | nil)
	local Command: any = Environment.load(COMMAND)
	local Fields: any = Environment.load(FIELDS)
	local Move: any = Environment.load(MOVE)
	local layout: any = Fields.compile(Game.fields)

	local commands: { { [string]: any } } = {}
	for position: number = 1, 9 do
		local command: { [string]: any } = Command.new()
		command.number = 100 - position
		command.fields = Game.high.command
		table.insert(commands, command)
	end

	local move: any = Move.new()
	Move.encode(move, commands, 5, 7, 0, 150, layout, Game.limits)

	-- A good Move first, so the refused one has acknowledgments to leave alone
	local incoming: any = Move.incoming()
	Move.decode(move.command, 7, 0, 150, move.commands, layout, Game.limits, incoming)

	-- The fourth command's buffer a byte short, which runs out in offset, its tenth field
	local short: buffer = buffer.create(Game.bytes.command - 1)
	buffer.copy(short, 0, move.commands[4].fields, 0, Game.bytes.command - 1)
	move.commands[4].fields = short
	local failed: number? = Move.decode(move.command, 9, 1, 200, move.commands, layout, Game.limits, incoming)
	if failed ~= 10 then
		return false, `A Move with one short command was refused at {failed}, where offset, field 10, runs out`
	elseif incoming.count ~= 0 then
		return false, `A refused Move left {incoming.count} commands decoded`
	elseif incoming.acknowledged ~= 7 or incoming.received ~= 0 or incoming.delay ~= 150 then
		return false, "A refused Move's acknowledgments were taken"
	end

	local refused: boolean, why: string =
		Refuses("carries 0 to 8 commands", Move.encode, move, commands, 9, 0, 0, 0, layout, Game.limits)
	if not refused then
		return false, `A Move of 9 commands was encoded: {why}`
	end

	-- Two commands with a gap between their numbers
	commands[2].number = 90
	refused, why = Refuses("out of order", Move.encode, move, commands, 2, 0, 0, 0, layout, Game.limits)
	if not refused then
		return false, `A Move with its commands out of order was encoded: {why}`
	end

	return true, nil
end
