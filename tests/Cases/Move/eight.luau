--[[
    A Move of 8 commands, numbered down across the u16 wrap, encodes into
    what Volt's client sends and decodes from what Volt's server hands its
    listener, with every command, its game fields and the acknowledgments
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local NEWEST: number = 3 -- So the eight run 3, 2, 1, 0, 65535, 65534, 65533, 65532
local ACKNOWLEDGED: number = 65535
local RECEIVED: number = 0xA5F0
local DELAY: number = 250
local STEPS: number = 3 -- Mock steps for a flush to reach the server
local CLOSE: number = 1e-9

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local replicatedStorage: any = globals.game:GetService("ReplicatedStorage")
	local tread: any = replicatedStorage.Packages.Tread

	-- The server first, so the player the client joins as is one it hears join
	local server: any = globals.require(tread.Network.Server)
	local client: any = globals.require(tread.Network.Client)
	local mock: any = globals.require(replicatedStorage.Packages.Volt).mock
	local Command: any = globals.require(tread.Codec.Command)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Move: any = globals.require(tread.Codec.Move)

	local layout: any = Fields.compile(Game.fields)

	local commands: { { [string]: any } } = {}
	for position: number = 1, 8 do
		local command: { [string]: any } = Command.new()
		command.number = (NEWEST - (position - 1)) % 65536
		command.right = (position - 4) / 127
		command.jump = position % 2 == 0
		command.yaw = position * 0.75
		command.fields = position % 2 == 0 and Game.high.command or Game.low.command
		table.insert(commands, command)
	end

	local move: any = Move.new()
	Move.encode(move, commands, #commands, ACKNOWLEDGED, RECEIVED, DELAY, layout, Game.limits)
	if move.command ~= NEWEST or #move.commands ~= 8 then
		return false, `The Move encoded as command {move.command} with {#move.commands} commands`
	end

	local arrived: { any }? = nil
	server.Move.on(function (...: any)
		arrived = { ... }
	end)

	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	for _ = 1, STEPS do
		mock:step()
	end

	if not arrived then
		return false, "The encoded Move never reached the server"
	end

	local incoming: any = Move.incoming()
	local _, command: number, acknowledged: number, received: number, delay: number, wires: any = table.unpack(arrived)
	local failed: number? = Move.decode(command, acknowledged, received, delay, wires, layout, Game.limits, incoming)
	if failed then
		return false, `The Move Volt delivered was refused at field {failed}`
	end

	if incoming.count ~= 8 or incoming.command ~= NEWEST then
		return false, `The Move decoded {incoming.count} commands from {incoming.command}`
	elseif incoming.acknowledged ~= ACKNOWLEDGED or incoming.received ~= RECEIVED or incoming.delay ~= DELAY then
		return false, "The Move's acknowledgments or delay decoded other than they were encoded"
	end

	for position: number = 1, 8 do
		local expected: { [string]: any } = Command.new()
		Command.read(move.commands[position], expected, layout, Game.limits)
		expected.number = commands[position].number

		local decoded: { [string]: any } = incoming.commands[position]
		local differs: string? = Same(expected, decoded, `command {position}`, CLOSE)
		if differs then
			return false, differs
		elseif decoded.number ~= commands[position].number then
			return false, `Command {position} decoded as number {decoded.number}, not {commands[position].number}`
		end
	end

	return true, nil
end
