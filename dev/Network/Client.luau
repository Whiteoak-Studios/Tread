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

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x28BB1F53,
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

	messages = {},

	outgoing = {
		[1] = { name = "press", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "corrected", kind = "event", reliable = true, minBytes = 6, maxBytes = 6 },
		[3] = { name = "shot", kind = "event", reliable = true, minBytes = 4, maxBytes = 6 },
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
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
