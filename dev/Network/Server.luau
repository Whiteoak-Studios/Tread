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
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never

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

local function writeshoot(slot_2: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if type(slot_2) ~= "number" or bit32.band(slot_2, 255) ~= slot_2 or slot_2 > 6 then
		refuseReliable("shoot.slot: expected u8(0..6)")
	end

	buffer.writeu8(out, offset + 1, slot_2)
end

local function writereport(kind: string, detail: string, dropped: number)
	local offset: number, out: buffer = beginReliable(87)
	buffer.writeu8(out, offset, 2)

	if type(kind) ~= "string" then
		refuseReliable("report.kind: expected string")
	end

	if #kind < 1 or #kind > 16 then
		refuseReliable("report.kind: length out of range")
	end

	buffer.writeu8(out, offset + 1, #kind - 1)

	if type(detail) ~= "string" then
		refuseReliable("report.detail: expected string")
	end

	if #detail > 64 then
		refuseReliable("report.detail: length out of range")
	end

	buffer.writeu8(out, offset + 2, #detail)

	if type(dropped) ~= "number" or bit32.band(dropped, 4294967295) ~= dropped then
		refuseReliable("report.dropped: expected u32")
	end

	buffer.writeu32(out, offset + 3, dropped)
	offset += 7
	buffer.writestring(out, offset, kind)
	offset += #kind
	buffer.writestring(out, offset, detail)
	offset += #detail
	trimReliable(offset)
end

local function writeclip(withheld: boolean, index: number, total: number, bytes: buffer)
	local offset: number, out: buffer = beginReliable(4102)
	buffer.writeu8(out, offset, 3)
	local flags: number = 0

	if type(withheld) ~= "boolean" then
		refuseReliable("clip.withheld: expected boolean")
	end

	flags += withheld and 1 or 0

	if type(index) ~= "number" or bit32.band(index, 255) ~= index or index < 1 then
		refuseReliable("clip.index: expected u8(1..255)")
	end

	buffer.writeu8(out, offset + 2, index)

	if type(total) ~= "number" or bit32.band(total, 255) ~= total or total < 1 then
		refuseReliable("clip.total: expected u8(1..255)")
	end

	buffer.writeu8(out, offset + 3, total)

	if type(bytes) ~= "buffer" then
		refuseReliable("clip.bytes: expected buffer")
	end

	if buffer.len(bytes) > 4096 then
		refuseReliable("clip.bytes: length out of range")
	end

	buffer.writeu16(out, offset + 4, buffer.len(bytes))
	buffer.writeu8(out, offset + 1, flags)
	offset += 6
	buffer.copy(out, offset, bytes)
	offset += buffer.len(bytes)
	trimReliable(offset)
end

local function readplayed(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 5 > length then
		error("played: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local time: number = buffer.readf32(packet, cursor + 1)

	if time ~= time then
		error("played.time: out of range")
	end

	cursor += 5

	return runtime:deliver(4, player, cursor, sideCursor, time, bit32.btest(flags, 1))
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x0E43105F,
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
		[4] = { name = "played", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readplayed },
	},

	outgoing = {
		[1] = { name = "shoot", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "report", kind = "event", reliable = true, minBytes = 8, maxBytes = 87 },
		[3] = { name = "clip", kind = "event", reliable = true, minBytes = 6, maxBytes = 4102 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

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

	shoot = table.freeze({
		fire = function (player: Player | Bot, slot_2: number)
			if (before[1] == nil or before[1](player, slot_2)) and runtime:target(player) then
				writeshoot(slot_2)
			end
		end,

		fireAll = function (slot_2: number)
			runtime:broadcast(1, nil, nil, writeshoot, slot_2)
		end,

		fireList = function (players: { Player | Bot }, slot_2: number)
			runtime:broadcast(1, players, nil, writeshoot, slot_2)
		end,

		fireExcept = function (player: Player | Bot, slot_2: number)
			runtime:broadcast(1, nil, player, writeshoot, slot_2)
		end,

		fireSet = function (players: { [Player | Bot]: true }, slot_2: number)
			runtime:broadcast(1, players, nil, writeshoot, slot_2)
		end,
	}) :: ServerEvent<(number)>,

	report = table.freeze({
		fire = function (player: Player | Bot, kind: string, detail: string, dropped: number)
			if (before[2] == nil or before[2](player, kind, detail, dropped)) and runtime:target(player) then
				writereport(kind, detail, dropped)
			end
		end,

		fireAll = function (kind: string, detail: string, dropped: number)
			runtime:broadcast(2, nil, nil, writereport, kind, detail, dropped)
		end,

		fireList = function (players: { Player | Bot }, kind: string, detail: string, dropped: number)
			runtime:broadcast(2, players, nil, writereport, kind, detail, dropped)
		end,

		fireExcept = function (player: Player | Bot, kind: string, detail: string, dropped: number)
			runtime:broadcast(2, nil, player, writereport, kind, detail, dropped)
		end,

		fireSet = function (players: { [Player | Bot]: true }, kind: string, detail: string, dropped: number)
			runtime:broadcast(2, players, nil, writereport, kind, detail, dropped)
		end,
	}) :: ServerEvent<(string, string, number)>,

	clip = table.freeze({
		fire = function (player: Player | Bot, withheld: boolean, index: number, total: number, bytes: buffer)
			if (before[3] == nil or before[3](player, withheld, index, total, bytes)) and runtime:target(player) then
				writeclip(withheld, index, total, bytes)
			end
		end,

		fireAll = function (withheld: boolean, index: number, total: number, bytes: buffer)
			runtime:broadcast(3, nil, nil, writeclip, withheld, index, total, bytes)
		end,

		fireList = function (players: { Player | Bot }, withheld: boolean, index: number, total: number, bytes: buffer)
			runtime:broadcast(3, players, nil, writeclip, withheld, index, total, bytes)
		end,

		fireExcept = function (player: Player | Bot, withheld: boolean, index: number, total: number, bytes: buffer)
			runtime:broadcast(3, nil, player, writeclip, withheld, index, total, bytes)
		end,

		fireSet = function (players: { [Player | Bot]: true }, withheld: boolean, index: number, total: number, bytes: buffer)
			runtime:broadcast(3, players, nil, writeclip, withheld, index, total, bytes)
		end,
	}) :: ServerEvent<(boolean, number, number, buffer)>,

	played = table.freeze({
		on = function (listener: (player: Player | Bot, time: number, stopped: boolean) -> ()): () -> ()
			return runtime:on(4, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number, boolean)
			return runtime:iter(4)
		end,
	}) :: ServerListener<(number, boolean)>,

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
	["shoot"] = Network.shoot,
	["report"] = Network.report,
	["clip"] = Network.clip,
	["played"] = Network.played,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
