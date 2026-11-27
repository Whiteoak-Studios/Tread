--[[
    What the Commands cases share: Commands started with Frontier Zero's
    ticks over the codec's fixture game, a bot's connection, every report
    fired, and Moves built and handed over as Volt's Move listener does
--]]

--!strict
local Intake = {}
Intake.__index = Intake

local Environment = require("../../Environment")
local Game = require("../Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local BOT: string = "Bot" -- The rig's bot's Name
local BOT_RTT: number = 0.1 -- Seconds the rig's bot connection reports
local WRAP: number = 2 ^ 16 -- A command number is a u16

-- One report a callback heard
export type Heard = {
	player: any,
	kind: string,
	measurement: number | string,
}

type Fields = {
	globals: any, -- The environment's game, script and require
	Commands: any,
	Connections: any,
	Command: any, -- The codec's
	Move: any,
	layout: any, -- The fixture game's declarations, compiled
	shared: any, -- Frontier Zero's shared table, with the fixture game's declarations
	bot: { Name: string },
	connection: any, -- The bot's
	heard: { Heard },
	move: any, -- The Move each send encodes into
}

-- A copy of a value with every table in it copied too
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local result: { [any]: any } = {}

	for key: any, inner: any in value do
		result[key] = copy(inner)
	end

	return result
end

--[[
    A fresh environment with Commands started, Connections started with a
    bot round trip, the bot's connection made and a callback hearing every
    report
--]]

function Intake.new(): Self
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = globals.game:GetService("ServerScriptService").Fixtures

	local Commands: any = globals.require(tread.Server.Commands)
	local Connections: any = globals.require(tread.Server.Connections)
	local Reports: any = globals.require(tread.Server.Reports)

	local shared: any = globals.require(fixtures.Config.Example).shared()
	shared.fields = Game.fields

	local layout: any = globals.require(tread.Codec.Fields).compile(Game.fields)
	local heard: { Heard } = {}

	Reports.connect(function (player: any, kind: string, measurement: number | string)
		table.insert(heard, { player = player, kind = kind, measurement = measurement })
	end)

	Commands.start(shared, layout)
	Connections.start(globals.require(fixtures.Config.Example).server().rewind.rttSmoothing, { rtt = BOT_RTT })

	local bot: { Name: string } = { Name = BOT }
	local Move: any = globals.require(tread.Codec.Move)

	return setmetatable({
		globals = globals,
		Commands = Commands,
		Connections = Connections,
		Command = globals.require(tread.Codec.Command),
		Move = Move,
		layout = layout,
		shared = shared,
		bot = bot,
		connection = Connections.add(bot),
		heard = heard,
		move = Move.new(),
	}, Intake)
end

--[[
    A command at rest numbered number, with the fixture game's lowest field
    values, for a case to change
--]]

function Intake.command(self: Self, number: number): any
	local command: any = self.Command.new()
	command.number = number % WRAP
	command.fields = copy(Game.low.command)

	return command
end

--[[
    Commands at rest numbered down from newest, newest first, the order a
    Move carries them in
--]]

function Intake.commands(self: Self, newest: number, count: number): { any }
	local commands: { any } = {}

	for position: number = 1, count do
		table.insert(commands, self:command(newest - (position - 1)))
	end

	return commands
end

--[[
    Encodes commands, newest first, into the rig's Move with the
    acknowledgments given, each 0 when left out, for a case to change its
    wires before it is delivered
--]]

function Intake.encode(self: Self, commands: { any }, acknowledged: number?, received: number?, delay: number?): any
	self.Move.encode(
		self.move,
		commands,
		#commands,
		acknowledged or 0,
		received or 0,
		delay or 0,
		self.layout,
		Game.limits
	)

	return self.move
end

--[[
    Hands the rig's Move to Commands as Volt's Move listener delivers one,
    from the rig's bot or from another connection given
--]]

function Intake.deliver(self: Self, connection: any?)
	local move: any = self.move
	local from: any = connection or self.connection

	self.Commands.receive(from, move.command, move.acknowledged, move.received, move.delay, move.commands)
end

--[[
    Encodes commands into a Move and delivers it from the rig's bot
--]]

function Intake.send(self: Self, commands: { any }, acknowledged: number?, received: number?, delay: number?)
	self:encode(commands, acknowledged, received, delay)
	self:deliver()
end

--[[
    What Commands.take gives the rig's bot for a tick
--]]

function Intake.take(self: Self, tick: number): (any, boolean, number)
	return self.Commands.take(self.connection, tick)
end

--[[
    The measurements reported of a kind, in the order they were fired
--]]

function Intake.reported(self: Self, kind: string): { number | string }
	local measurements: { number | string } = {}

	for _, heard: Heard in self.heard do
		if heard.kind == kind then
			table.insert(measurements, heard.measurement)
		end
	end

	return measurements
end

export type Intake = Self
type Self = typeof(setmetatable({} :: Fields, Intake))

return Intake
