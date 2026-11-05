--[[
    The server module Volt 0.1.0 generated from Dev.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

type Bot = Volt.Bot

export type ServerEvent<A...> = {
	fire: (player: Player | Bot, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player | Bot }, A...) -> (),
	fireExcept: (player: Player | Bot, A...) -> (),
	fireSet: (players: { [Player | Bot]: true }, A...) -> (),
}

export type ServerListener<A...> = {
	on: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player | Bot, A...),
}

export type ServerPolling<A...> = { iter: () -> () -> (number, Player | Bot, A...) }

export type ServerFunction<A..., R...> = {
	on: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),
}

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime

local function readpress(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("press: truncated")
	end

	local platform: number = buffer.readu8(packet, cursor)

	if platform < 1 or platform > 127 then
		error("press.platform: out of range")
	end

	cursor += 1

	return runtime:deliver(1, player, cursor, sideCursor, platform)
end

local function readcorrected(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 5 > length then
		error("corrected: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local size: number = buffer.readf32(packet, cursor + 1)

	if size ~= size then
		error("corrected.size: out of range")
	end

	cursor += 5

	return runtime:deliver(2, player, cursor, sideCursor, size, bit32.btest(flags, 1))
end

local function readshot(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("shot: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local sequence: number = buffer.readu16(packet, cursor + 1)
	local target: number?
	cursor += 3

	if bit32.btest(flags, 1) then
		if cursor + 2 > length then
			error("shot.target: truncated")
		end

		local target_2: number = buffer.readu16(packet, cursor)
		cursor += 2
		target = target_2
	end

	return runtime:deliver(3, player, cursor, sideCursor, sequence, target)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x28BB1F53,
	scope = "Dev",
	side = "server",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxOutgoing = 262144,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
		writeValidation = true,
	},

	messages = {
		[1] = { name = "press", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readpress },
		[2] = { name = "corrected", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readcorrected },
		[3] = { name = "shot", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readshot },
	},

	outgoing = {},
})

local Network = {
	press = table.freeze({
		on = function (listener: (player: Player | Bot, platform: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number)
			return runtime:iter(1)
		end,
	}) :: ServerListener<(number)>,

	corrected = table.freeze({
		on = function (listener: (player: Player | Bot, size: number, flagged: boolean) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number, boolean)
			return runtime:iter(2)
		end,
	}) :: ServerListener<(number, boolean)>,

	shot = table.freeze({
		on = function (listener: (player: Player | Bot, sequence: number, target: number?) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number, number?)
			return runtime:iter(3)
		end,
	}) :: ServerListener<(number, number?)>,

	version = "0.1.0",

	hooks = table.freeze({
		beforeSend = runtime.beforeSend,
		afterReceive = runtime.afterReceive,
	}),

	rate = runtime.rate,

	flush = function ()
		runtime:flush()
	end,

	onFailure = function (handler: Volt.Failure): Volt.Failure
		return runtime:onFailure(handler)
	end,

	stats = function (player: (Player | Bot)?): Volt.Stats
		return runtime:stats(player)
	end,

	onJoin = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onJoin(callback)
	end,

	onLeave = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onLeave(callback)
	end,

	onHandshake = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onHandshake(callback)
	end,

	traffic = function (player: Player | Bot): (number, number)
		return runtime:traffic(player)
	end,

	budget = function (bytesPerSecond: number?)
		runtime:budget(bytesPerSecond)
	end,

	isBot = runtime.isBot,
}

Network.events = table.freeze({
	["press"] = Network.press,
	["corrected"] = Network.corrected,
	["shot"] = Network.shot,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
