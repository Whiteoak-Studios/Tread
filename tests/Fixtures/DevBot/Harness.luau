--[[
    What the bot harness's cases share: its modules loaded as the dev place
    runs them, the example's encoding context, a stand-in client side that
    keeps every Move fired, and the server messages a case hands a bot
--]]

--!strict
local DevServer = require("../DevServer/Harness")

local WRAP: number = 2 ^ 16 -- A command number is a u16

-- One command of a Move as the bot fired it, copied, since the bot reuses its wires
export type Wire = {
	number: number,
	moveX: number,
	moveZ: number,
	buttons: number,
	yaw: number,
	pitch: number,
	fields: number, -- The length of its game fields
}

-- One Move as the bot fired it
export type Fired = {
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	commands: { Wire }, -- Newest first
	flushes: number, -- The flushes made before it was fired
}

-- A stand-in for a bot's client side of Tread's scope
export type Side = {
	network: any, -- What Bot.new takes, shaped as the generated client module is
	fired: { Fired },
	flushes: number,
	listeners: { [string]: (...any) -> () }, -- Each event's listener, while it is connected
}

export type Loaded = {
	loaded: DevServer.Loaded,
	Bot: any,
	Programs: any,
	Seeded: any,
	Config: any,
	Block: any,
	Constants: any,
	OwnerState: any,
	State: any,
	shared: any, -- The example's shared table
	context: any, -- The bot harness's context over it
}

-- The events the server sends a client on Tread's scope, which a client side hears
local HEARD: { string } = { "Relay", "Withheld", "Owner", "Feed", "Slots", "Death", "Platform", "Spectate", "Shared" }

local Harness = {}

--[[
    The bot harness's modules in the dev server's fake game, with Tread's
    codecs, the example's shared table and the context a bot encodes with
--]]

function Harness.load(): Loaded
	local loaded: DevServer.Loaded = DevServer.load()
	local services: any = loaded.game:GetService("ServerScriptService")
	local bots: any = services.Server.Bots
	local tread: any = loaded.game:GetService("ReplicatedStorage").Packages.Tread

	local Bot: any = loaded.require(bots.Bot)
	local Config: any = loaded.require(bots.Config)
	local shared: any = loaded.require(services.Fixtures.Config.Example).shared()

	return {
		loaded = loaded,
		Bot = Bot,
		Programs = loaded.require(bots.Programs),
		Seeded = loaded.require(bots.Seeded),
		Config = Config,
		Block = loaded.require(tread.Codec.Block),
		Constants = loaded.require(tread.Constants),
		OwnerState = loaded.require(tread.Codec.OwnerState),
		State = loaded.require(tread.Step.State),
		shared = shared,
		context = Bot.context(shared, Config.delay, Config.fields),
	}
end

--[[
    A stand-in client side: its Move keeps a copy of every Move fired, its
    flush counts, and each event the server sends keeps the listener the
    bot connected until the bot disconnects it
--]]

function Harness.side(): Side
	local side: Side = { network = nil, fired = {}, flushes = 0, listeners = {} }
	local events: { [string]: any } = {}

	for _, name: string in HEARD do
		events[name] = {
			on = function (listener: (...any) -> ()): () -> ()
				side.listeners[name] = listener

				return function ()
					side.listeners[name] = nil
				end
			end,
		}
	end

	local move: any = {
		fire = function (command: number, acknowledged: number, received: number, delay: number, commands: { any })
			local wires: { Wire } = {}
			for index: number, wire: any in commands do
				table.insert(wires, {
					number = (command - (index - 1)) % WRAP,
					moveX = wire.moveX,
					moveZ = wire.moveZ,
					buttons = wire.buttons,
					yaw = wire.yaw,
					pitch = wire.pitch,
					fields = buffer.len(wire.fields),
				})
			end

			table.insert(side.fired, {
				command = command,
				acknowledged = acknowledged,
				received = received,
				delay = delay,
				commands = wires,
				flushes = side.flushes,
			})
		end,
	}

	events.Move = move

	side.network = {
		events = events,
		Move = move,

		flush = function ()
			side.flushes += 1
		end,
	}

	return side
end

-- OwnerState's bytes for a body at a position, moving at a velocity, after a command on a tick
function Harness.owner(harness: Loaded, position: vector, velocity: vector, command: number, tick: number): buffer
	local state: any = harness.State.new()
	state.position = position
	state.velocity = velocity
	state.command = command
	state.tick = tick

	-- Each game block starts at its declarations' rest, as a server's new body's does
	state.block.sinceJump = 0
	state.block.sinceShot = 0
	state.fields.beingRevived = false

	local scratch: buffer = buffer.create(harness.Constants.MAX_OWNER_STATE)
	local length: number = harness.OwnerState.write(state, scratch, 0, harness.context.layout, harness.context.limits)
	local data: buffer = buffer.create(length)
	buffer.copy(data, 0, scratch, 0, length)

	return data
end

-- A relay block's bytes, empty but for its sequence
function Harness.relay(harness: Loaded, sequence: number): buffer
	local block: any = harness.Block.new()
	block.sequence = sequence

	local scratch: buffer = buffer.create(harness.Constants.MAX_RELAY_BYTES)
	local length: number = harness.Block.write(block, scratch)
	local data: buffer = buffer.create(length)
	buffer.copy(data, 0, scratch, 0, length)

	return data
end

return Harness
