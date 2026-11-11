--[[
    The client module Volt 0.1.0 generated from Dev.volt: a writer per
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

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientPolling<A...> = { iter: () -> () -> (number, A...) }

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never

local RUNREPORT_STATE: { "Refused" | "Running" | "Piece" | "Passed" | "Failed" } = { "Refused", "Running", "Piece", "Passed", "Failed" }

local BOTSPAWN_BEHAVIOR: { "Idle" | "Walk" | "Sprint" } = { "Idle", "Walk", "Sprint" }

local function writepress(platform: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if type(platform) ~= "number" or bit32.band(platform, 255) ~= platform or platform < 1 or platform > 127 then
		refuseReliable("press.platform: expected u8(1..127)")
	end

	buffer.writeu8(out, offset + 1, platform)
end

local function writecorrected(size: number, flagged: boolean)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 2)
	local flags: number = 0

	if type(size) ~= "number" or size ~= size then
		refuseReliable("corrected.size: expected f32")
	end

	buffer.writef32(out, offset + 2, size)

	if type(flagged) ~= "boolean" then
		refuseReliable("corrected.flagged: expected boolean")
	end

	flags += flagged and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
end

local function writeshot(sequence: number, target: number?)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 3)
	local flags: number = 0

	if type(sequence) ~= "number" or bit32.band(sequence, 65535) ~= sequence then
		refuseReliable("shot.sequence: expected u16")
	end

	buffer.writeu16(out, offset + 2, sequence)
	flags += target ~= nil and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
	offset += 4

	if target ~= nil then
		if type(target) ~= "number" or bit32.band(target, 65535) ~= target then
			refuseReliable("shot.target: expected u16")
		end

		buffer.writeu16(out, offset, target)
		offset += 2
	end

	trimReliable(offset)
end

local function readshoot(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("shoot: truncated")
	end

	local slot_2: number = buffer.readu8(packet, cursor)

	if slot_2 > 6 then
		error("shoot.slot: out of range")
	end

	cursor += 1

	return runtime:deliver(1, player, cursor, sideCursor, slot_2)
end

local function readreport(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 6 > length then
		error("report: truncated")
	end

	local kindLength: number = 1 + buffer.readu8(packet, cursor)

	if kindLength > 16 then
		error("report.kind: length out of range")
	end

	local detailLength: number = buffer.readu8(packet, cursor + 1)

	if detailLength > 64 then
		error("report.detail: length out of range")
	end

	local dropped: number = buffer.readu32(packet, cursor + 2)
	cursor += 6

	if cursor + kindLength > length then
		error("report.kind: truncated")
	end

	local kind: string = buffer.readstring(packet, cursor, kindLength)
	cursor += kindLength

	if cursor + detailLength > length then
		error("report.detail: truncated")
	end

	local detail: string = buffer.readstring(packet, cursor, detailLength)
	cursor += detailLength

	return runtime:deliver(2, player, cursor, sideCursor, kind, detail, dropped)
end

local function readclip(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 5 > length then
		error("clip: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local index: number = buffer.readu8(packet, cursor + 1)

	if index < 1 then
		error("clip.index: out of range")
	end

	local total: number = buffer.readu8(packet, cursor + 2)

	if total < 1 then
		error("clip.total: out of range")
	end

	local bytesLength: number = buffer.readu16(packet, cursor + 3)

	if bytesLength > 4096 then
		error("clip.bytes: length out of range")
	end

	cursor += 5

	if cursor + bytesLength > length then
		error("clip.bytes: truncated")
	end

	local bytes: buffer = buffer.create(bytesLength)
	buffer.copy(bytes, 0, packet, cursor, bytesLength)

	cursor += bytesLength

	return runtime:deliver(3, player, cursor, sideCursor, bit32.btest(flags, 1), index, total, bytes)
end

local function writeplayed(time: number, stopped: boolean)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 4)
	local flags: number = 0

	if type(time) ~= "number" or time ~= time then
		refuseReliable("played.time: expected f32")
	end

	buffer.writef32(out, offset + 2, time)

	if type(stopped) ~= "boolean" then
		refuseReliable("played.stopped: expected boolean")
	end

	flags += stopped and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
end

local function writerun(name: string)
	local offset: number, out: buffer = beginReliable(34)
	buffer.writeu8(out, offset, 5)

	if type(name) ~= "string" then
		refuseReliable("run.name: expected string")
	end

	if #name < 1 or #name > 32 then
		refuseReliable("run.name: length out of range")
	end

	buffer.writeu8(out, offset + 1, #name - 1)
	offset += 2
	buffer.writestring(out, offset, name)
	offset += #name
	trimReliable(offset)
end

local function readrunReport(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("runReport: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local state: ("Refused" | "Running" | "Piece" | "Passed" | "Failed")? = RUNREPORT_STATE[bit32.extract(flags, 0, 3) + 1]

	if not state then
		error("runReport.state: out of range")
	end

	local textLength: number = buffer.readu16(packet, cursor + 1)

	if textLength > 4000 then
		error("runReport.text: length out of range")
	end

	cursor += 3

	if cursor + textLength > length then
		error("runReport.text: truncated")
	end

	local text: string = buffer.readstring(packet, cursor, textLength)
	cursor += textLength

	return runtime:deliver(4, player, cursor, sideCursor, state, text)
end

local function writeclientCost(label: string, measured: boolean, line: string)
	local offset: number, out: buffer = beginReliable(581)
	buffer.writeu8(out, offset, 6)
	local flags: number = 0

	if type(label) ~= "string" then
		refuseReliable("clientCost.label: expected string")
	end

	if #label < 1 or #label > 64 then
		refuseReliable("clientCost.label: length out of range")
	end

	buffer.writeu8(out, offset + 2, #label - 1)

	if type(measured) ~= "boolean" then
		refuseReliable("clientCost.measured: expected boolean")
	end

	flags += measured and 1 or 0

	if type(line) ~= "string" then
		refuseReliable("clientCost.line: expected string")
	end

	if #line < 1 or #line > 512 then
		refuseReliable("clientCost.line: length out of range")
	end

	buffer.writeu16(out, offset + 3, #line - 1)
	buffer.writeu8(out, offset + 1, flags)
	offset += 5
	buffer.writestring(out, offset, label)
	offset += #label
	buffer.writestring(out, offset, line)
	offset += #line
	trimReliable(offset)
end

local function writebotSpawn(count: number, behavior: "Idle" | "Walk" | "Sprint", radius: number?)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 7)
	local flags: number = 0

	if type(count) ~= "number" or bit32.band(count, 65535) ~= count then
		refuseReliable("botSpawn.count: expected u16")
	end

	buffer.writeu16(out, offset + 2, count)
	local behaviorIndex: number = table.find(BOTSPAWN_BEHAVIOR, behavior) or 0

	if behaviorIndex == 0 then
		refuseReliable("botSpawn.behavior: expected enum { Idle, Walk, Sprint }")
	end

	flags += behaviorIndex - 1
	flags += radius ~= nil and 4 or 0
	buffer.writeu8(out, offset + 1, flags)
	offset += 4

	if radius ~= nil then
		if type(radius) ~= "number" or bit32.band(radius, 65535) ~= radius or radius < 1 or radius > 8192 then
			refuseReliable("botSpawn.radius: expected u16(1..8192)")
		end

		buffer.writeu16(out, offset, radius)
		offset += 2
	end

	trimReliable(offset)
end

local function writebotClear()
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 8)
end

local function writebotWatch(shown: boolean)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 9)
	local flags: number = 0

	if type(shown) ~= "boolean" then
		refuseReliable("botWatch.shown: expected boolean")
	end

	flags += shown and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
end

local function readbotRefused(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("botRefused: truncated")
	end

	local reasonLength: number = 1 + buffer.readu8(packet, cursor)

	if reasonLength > 200 then
		error("botRefused.reason: length out of range")
	end

	cursor += 1

	if cursor + reasonLength > length then
		error("botRefused.reason: truncated")
	end

	local reason: string = buffer.readstring(packet, cursor, reasonLength)
	cursor += reasonLength

	return runtime:deliver(5, player, cursor, sideCursor, reason)
end

local function readbotStats(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("botStats: truncated")
	end

	local made: number = buffer.readu16(packet, cursor)
	local textLength: number = buffer.readu16(packet, cursor + 2)

	if textLength > 1000 then
		error("botStats.text: length out of range")
	end

	cursor += 4

	if cursor + textLength > length then
		error("botStats.text: truncated")
	end

	local text: string = buffer.readstring(packet, cursor, textLength)
	cursor += textLength

	return runtime:deliver(6, player, cursor, sideCursor, made, text)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x0A7B4066,
	scope = "Dev",
	side = "client",
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
		[1] = { name = "shoot", kind = "event", mode = "SingleSync", queue = 64, read = readshoot },
		[2] = { name = "report", kind = "event", mode = "SingleSync", queue = 64, read = readreport },
		[3] = { name = "clip", kind = "event", mode = "SingleSync", queue = 64, read = readclip },
		[4] = { name = "runReport", kind = "event", mode = "SingleSync", queue = 64, read = readrunReport },
		[5] = { name = "botRefused", kind = "event", mode = "SingleSync", queue = 64, read = readbotRefused },
		[6] = { name = "botStats", kind = "event", mode = "SingleSync", queue = 64, read = readbotStats },
	},

	outgoing = {
		[1] = { name = "press", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "corrected", kind = "event", reliable = true, minBytes = 6, maxBytes = 6 },
		[3] = { name = "shot", kind = "event", reliable = true, minBytes = 4, maxBytes = 6 },
		[4] = { name = "played", kind = "event", reliable = true, minBytes = 6, maxBytes = 6 },
		[5] = { name = "run", kind = "event", reliable = true, minBytes = 3, maxBytes = 34 },
		[6] = { name = "clientCost", kind = "event", reliable = true, minBytes = 7, maxBytes = 581 },
		[7] = { name = "botSpawn", kind = "event", reliable = true, minBytes = 4, maxBytes = 6 },
		[8] = { name = "botClear", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
		[9] = { name = "botWatch", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	press = table.freeze({
		fire = function (platform: number)
			if before[1] == nil or before[1](nil, platform) then
				writepress(platform)
			end
		end,
	}) :: ClientEvent<(number)>,

	corrected = table.freeze({
		fire = function (size: number, flagged: boolean)
			if before[2] == nil or before[2](nil, size, flagged) then
				writecorrected(size, flagged)
			end
		end,
	}) :: ClientEvent<(number, boolean)>,

	shot = table.freeze({
		fire = function (sequence: number, target: number?)
			if before[3] == nil or before[3](nil, sequence, target) then
				writeshot(sequence, target)
			end
		end,
	}) :: ClientEvent<(number, number?)>,

	shoot = table.freeze({
		on = function (listener: (slot_2: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(1)
		end,
	}) :: ClientListener<(number)>,

	report = table.freeze({
		on = function (listener: (kind: string, detail: string, dropped: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, string, string, number)
			return runtime:iter(2)
		end,
	}) :: ClientListener<(string, string, number)>,

	clip = table.freeze({
		on = function (listener: (withheld: boolean, index: number, total: number, bytes: buffer) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, boolean, number, number, buffer)
			return runtime:iter(3)
		end,
	}) :: ClientListener<(boolean, number, number, buffer)>,

	played = table.freeze({
		fire = function (time: number, stopped: boolean)
			if before[4] == nil or before[4](nil, time, stopped) then
				writeplayed(time, stopped)
			end
		end,
	}) :: ClientEvent<(number, boolean)>,

	run = table.freeze({
		fire = function (name: string)
			if before[5] == nil or before[5](nil, name) then
				writerun(name)
			end
		end,
	}) :: ClientEvent<(string)>,

	runReport = table.freeze({
		on = function (listener: (state: "Refused" | "Running" | "Piece" | "Passed" | "Failed", text: string) -> ()): () -> ()
			return runtime:on(4, listener)
		end,

		iter = function (): () -> (number, "Refused" | "Running" | "Piece" | "Passed" | "Failed", string)
			return runtime:iter(4)
		end,
	}) :: ClientListener<("Refused" | "Running" | "Piece" | "Passed" | "Failed", string)>,

	clientCost = table.freeze({
		fire = function (label: string, measured: boolean, line: string)
			if before[6] == nil or before[6](nil, label, measured, line) then
				writeclientCost(label, measured, line)
			end
		end,
	}) :: ClientEvent<(string, boolean, string)>,

	botSpawn = table.freeze({
		fire = function (count: number, behavior: "Idle" | "Walk" | "Sprint", radius: number?)
			if before[7] == nil or before[7](nil, count, behavior, radius) then
				writebotSpawn(count, behavior, radius)
			end
		end,
	}) :: ClientEvent<(number, "Idle" | "Walk" | "Sprint", number?)>,

	botClear = table.freeze({
		fire = function ()
			if before[8] == nil or before[8](nil) then
				writebotClear()
			end
		end,
	}) :: ClientEvent<()>,

	botWatch = table.freeze({
		fire = function (shown: boolean)
			if before[9] == nil or before[9](nil, shown) then
				writebotWatch(shown)
			end
		end,
	}) :: ClientEvent<(boolean)>,

	botRefused = table.freeze({
		on = function (listener: (reason: string) -> ()): () -> ()
			return runtime:on(5, listener)
		end,

		iter = function (): () -> (number, string)
			return runtime:iter(5)
		end,
	}) :: ClientListener<(string)>,

	botStats = table.freeze({
		on = function (listener: (made: number, text: string) -> ()): () -> ()
			return runtime:on(6, listener)
		end,

		iter = function (): () -> (number, number, string)
			return runtime:iter(6)
		end,
	}) :: ClientListener<(number, string)>,

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
}

Network.events = table.freeze({
	["press"] = Network.press,
	["corrected"] = Network.corrected,
	["shot"] = Network.shot,
	["shoot"] = Network.shoot,
	["report"] = Network.report,
	["clip"] = Network.clip,
	["played"] = Network.played,
	["run"] = Network.run,
	["runReport"] = Network.runReport,
	["clientCost"] = Network.clientCost,
	["botSpawn"] = Network.botSpawn,
	["botClear"] = Network.botClear,
	["botWatch"] = Network.botWatch,
	["botRefused"] = Network.botRefused,
	["botStats"] = Network.botStats,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
