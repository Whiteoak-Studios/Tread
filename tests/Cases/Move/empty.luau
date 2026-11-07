--[[
    A Move with no commands is valid and carries only its acknowledgments,
    and a shorter Move after a longer one sends only its own commands while
    reusing the wires the longer one made
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local COMMAND: string = "src/Codec/Command.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local MOVE: string = "src/Codec/Move.luau"

return function (): (boolean, string | nil)
	local Command: any = Environment.load(COMMAND)
	local Fields: any = Environment.load(FIELDS)
	local Move: any = Environment.load(MOVE)
	local layout: any = Fields.compile(Game.fields)

	local move: any = Move.new()
	Move.encode(move, {}, 0, 41, 1, 150, layout, Game.limits)
	if move.command ~= 0 or #move.commands ~= 0 or move.acknowledged ~= 41 or move.received ~= 1 then
		return false, "A Move of no commands encoded something other than its acknowledgments"
	end

	local incoming: any = Move.incoming()
	if Move.decode(0, 41, 1, 150, {}, layout, Game.limits, incoming) ~= nil then
		return false, "A Move of no commands was refused"
	elseif incoming.count ~= 0 or incoming.acknowledged ~= 41 or incoming.received ~= 1 or incoming.delay ~= 150 then
		return false, "A Move of no commands decoded without its acknowledgments"
	end

	-- Four commands, then two: the second sends two, from the first two wires the four made
	local commands: { { [string]: any } } = {}
	for position: number = 1, 4 do
		local command: { [string]: any } = Command.new()
		command.number = 20 - position
		command.fields = Game.low.command
		table.insert(commands, command)
	end

	Move.encode(move, commands, 4, 41, 1, 150, layout, Game.limits)
	local first: any, second: any = move.commands[1], move.commands[2]

	Move.encode(move, commands, 2, 42, 3, 150, layout, Game.limits)
	if #move.commands ~= 2 or move.commands[1] ~= first or move.commands[2] ~= second or #move.wires ~= 4 then
		return false, `A shorter Move sent {#move.commands} commands over {#move.wires} wires, where it sends 2 of 4`
	elseif move.command ~= 19 or move.acknowledged ~= 42 or move.received ~= 3 then
		return false, "A shorter Move kept the last one's numbers"
	end

	return true, nil
end
