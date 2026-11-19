--[[
    Each command's check goes through Volt's Move as encoded, 0 and the
    largest u32 in every position, a Move encoded with no checks carries 0
    in each, reused wires too, and the decode reads none of it
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local COUNT: number = 8 -- The most a Move carries, so every position is crossed
local NEWEST: number = 40
local LARGEST: number = 2 ^ 32 - 1
local STEPS: number = 3 -- Mock steps for a flush to reach the server

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

	if Command.wire().check ~= 0 then
		return false, `A wire at rest holds check {Command.wire().check}, not 0`
	end

	local commands: { { [string]: any } } = {}
	for position: number = 1, COUNT do
		local command: { [string]: any } = Command.new()
		command.number = NEWEST - (position - 1)
		command.forward = position / COUNT
		command.fields = position % 2 == 0 and Game.high.command or Game.low.command
		table.insert(commands, command)
	end

	local arrived: { any }? = nil
	server.Move.on(function (...: any)
		arrived = { ... }
	end)

	-- Encodes the commands with the checks given, sends them through Volt, and gives the wires its server delivered
	local function through(checks: { number }?): { any }
		local move: any = Move.new()
		Move.encode(move, commands, COUNT, 0, 0, 0, layout, Game.limits, checks)

		arrived = nil
		client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
		client.flush()
		for _ = 1, STEPS do
			mock:step()
		end

		local heard: { any }? = arrived
		if not heard then
			error("The encoded Move never reached the server")
		end

		return heard[6]
	end

	-- 0 and the largest u32 in turn, then the other way round, so each position carries both
	local alternate: { number } = {}
	local opposite: { number } = {}
	for position: number = 1, COUNT do
		alternate[position] = position % 2 == 0 and LARGEST or 0
		opposite[position] = position % 2 == 0 and 0 or LARGEST
	end

	local decoded: { any } = {}
	for _, checks: { number } in { alternate, opposite } do
		local wires: { any } = through(checks)
		for position: number = 1, COUNT do
			if wires[position].check ~= checks[position] then
				return false, `Position {position} arrived with check {wires[position].check}, not {checks[position]}`
			end
		end

		-- The decode gives each command the same however its check was set
		local incoming: any = Move.incoming()
		local failed: number? = Move.decode(NEWEST, 0, 0, 0, wires, layout, Game.limits, incoming)
		if failed then
			return false, `A Move with checks was refused at field {failed}`
		end

		table.insert(decoded, incoming.commands)
	end

	local differs: string? = Same(decoded[1], decoded[2], "the commands decoded")
	if differs then
		return false, `The decode read the checks: {differs}`
	end

	-- Encoded with no checks, every position carries 0, a wire reused from a Move that carried checks included
	local move: any = Move.new()
	Move.encode(move, commands, COUNT, 0, 0, 0, layout, Game.limits, opposite)
	Move.encode(move, commands, COUNT, 0, 0, 0, layout, Game.limits)
	for position: number = 1, COUNT do
		if move.commands[position].check ~= 0 then
			return false, `A reused wire at position {position} kept check {move.commands[position].check}`
		end
	end

	for position: number, wire: any in through(nil) do
		if wire.check ~= 0 then
			return false, `A Move encoded with no checks arrived with check {wire.check} at position {position}`
		end
	end

	return true, nil
end
