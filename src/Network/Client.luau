--[[
    The client module Volt 0.1.0 generated from Tread.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Command = { moveX: number, moveZ: number, buttons: number, yaw: number, pitch: number, lean: number, headYaw: number, headPitch: number, fields: buffer }
export type Rig = "A" | "B"
export type SlotEntry = { slot: number, taken: { rig: Rig, player: Instance? }? }

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
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local trimUnreliable: (number) -> ()
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()

local SLOTS_TAKEN_RIG: { "A" | "B" } = { "A", "B" }

local function writeMove(command: number, acknowledged: number, received: number, delay: number, commands: { Command })
	local offset: number, out: buffer = beginUnreliable(617)
	buffer.writeu8(out, offset, 1)

	if type(command) ~= "number" or bit32.band(command, 65535) ~= command then
		refuseUnreliable("Move.command: expected u16")
	end

	buffer.writeu16(out, offset + 1, command)

	if type(acknowledged) ~= "number" or bit32.band(acknowledged, 65535) ~= acknowledged then
		refuseUnreliable("Move.acknowledged: expected u16")
	end

	buffer.writeu16(out, offset + 3, acknowledged)

	if type(received) ~= "number" or bit32.band(received, 65535) ~= received then
		refuseUnreliable("Move.received: expected u16")
	end

	buffer.writeu16(out, offset + 5, received)

	if type(delay) ~= "number" or bit32.band(delay, 255) ~= delay then
		refuseUnreliable("Move.delay: expected u8")
	end

	buffer.writeu8(out, offset + 7, delay)

	if type(commands) ~= "table" then
		refuseUnreliable("Move.commands: expected table")
	end

	if #commands > 8 then
		refuseUnreliable("Move.commands: length out of range")
	end

	buffer.writeu8(out, offset + 8, #commands)
	offset += 9

	for index = 1, #commands do
		local commandsEntry = commands[index]

		if type(commandsEntry) ~= "table" then
			refuseUnreliable("Move.commands[]: expected table")
		end

		local moveX = commandsEntry.moveX

		if type(moveX) ~= "number" or moveX % 1 ~= 0 or moveX < -127 or moveX > 127 then
			refuseUnreliable("Move.commands[].moveX: expected i8(-127..127)")
		end

		buffer.writei8(out, offset, moveX)
		local moveZ = commandsEntry.moveZ

		if type(moveZ) ~= "number" or moveZ % 1 ~= 0 or moveZ < -127 or moveZ > 127 then
			refuseUnreliable("Move.commands[].moveZ: expected i8(-127..127)")
		end

		buffer.writei8(out, offset + 1, moveZ)
		local buttons = commandsEntry.buttons

		if type(buttons) ~= "number" or bit32.band(buttons, 65535) ~= buttons then
			refuseUnreliable("Move.commands[].buttons: expected u16")
		end

		buffer.writeu16(out, offset + 2, buttons)
		local yaw = commandsEntry.yaw

		if type(yaw) ~= "number" or bit32.band(yaw, 65535) ~= yaw then
			refuseUnreliable("Move.commands[].yaw: expected u16")
		end

		buffer.writeu16(out, offset + 4, yaw)
		local pitch = commandsEntry.pitch

		if type(pitch) ~= "number" or pitch % 1 ~= 0 or pitch < -16384 or pitch > 16384 then
			refuseUnreliable("Move.commands[].pitch: expected i16(-16384..16384)")
		end

		buffer.writei16(out, offset + 6, pitch)
		local lean = commandsEntry.lean

		if type(lean) ~= "number" or lean % 1 ~= 0 or lean < -127 or lean > 127 then
			refuseUnreliable("Move.commands[].lean: expected i8(-127..127)")
		end

		buffer.writei8(out, offset + 8, lean)
		local headYaw = commandsEntry.headYaw

		if type(headYaw) ~= "number" or headYaw % 1 ~= 0 or headYaw < -127 or headYaw > 127 then
			refuseUnreliable("Move.commands[].headYaw: expected i8(-127..127)")
		end

		buffer.writei8(out, offset + 9, headYaw)
		local headPitch = commandsEntry.headPitch

		if type(headPitch) ~= "number" or headPitch % 1 ~= 0 or headPitch < -127 or headPitch > 127 then
			refuseUnreliable("Move.commands[].headPitch: expected i8(-127..127)")
		end

		buffer.writei8(out, offset + 10, headPitch)
		local fields = commandsEntry.fields

		if type(fields) ~= "buffer" then
			refuseUnreliable("Move.commands[].fields: expected buffer")
		end

		if buffer.len(fields) > 64 then
			refuseUnreliable("Move.commands[].fields: length out of range")
		end

		buffer.writeu8(out, offset + 11, buffer.len(fields))
		offset += 12
		buffer.copy(out, offset, fields)
		offset += buffer.len(fields)
	end

	trimUnreliable(offset)
	markUnreliable()
end

local function readRelay(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Relay: truncated")
	end

	local valueLength: number = buffer.readu16(packet, cursor)

	if valueLength > 896 then
		error("Relay: length out of range")
	end

	cursor += 2

	if cursor + valueLength > length then
		error("Relay: truncated")
	end

	local value: buffer = buffer.create(valueLength)
	buffer.copy(value, 0, packet, cursor, valueLength)

	cursor += valueLength

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function readWithheld(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Withheld: truncated")
	end

	local valueLength: number = buffer.readu16(packet, cursor)

	if valueLength > 896 then
		error("Withheld: length out of range")
	end

	cursor += 2

	if cursor + valueLength > length then
		error("Withheld: truncated")
	end

	local value: buffer = buffer.create(valueLength)
	buffer.copy(value, 0, packet, cursor, valueLength)

	cursor += valueLength

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function readOwner(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Owner: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 96 then
		error("Owner: length out of range")
	end

	cursor += 1

	if cursor + valueLength > length then
		error("Owner: truncated")
	end

	local value: buffer = buffer.create(valueLength)
	buffer.copy(value, 0, packet, cursor, valueLength)

	cursor += valueLength

	return runtime:deliver(3, player, cursor, sideCursor, value)
end

local function readFeed(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Feed: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 160 then
		error("Feed: length out of range")
	end

	cursor += 1

	if cursor + valueLength > length then
		error("Feed: truncated")
	end

	local value: buffer = buffer.create(valueLength)
	buffer.copy(value, 0, packet, cursor, valueLength)

	cursor += valueLength

	return runtime:deliver(4, player, cursor, sideCursor, value)
end

local function readSlots(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Slots: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)
	cursor += 1

	if cursor + 3 * valueLength > length then
		error("Slots: truncated")
	end

	local value: { SlotEntry } = table.create(valueLength) :: { SlotEntry }

	for index = 1, valueLength do
		if cursor + 3 > length then
			error("Slots: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local slot_2: number = buffer.readu16(packet, cursor + 1)
		local taken: { rig: Rig, player: Instance? }?
		cursor += 3

		if bit32.btest(flags, 1) then
			if cursor + 1 > length then
				error("Slots[].taken: truncated")
			end

			local flags_2: number = buffer.readu8(packet, cursor)
			local rig: ("A" | "B")? = SLOTS_TAKEN_RIG[bit32.extract(flags_2, 0, 1) + 1]

			if not rig then
				error("Slots[].taken.rig: out of range")
			end

			local player_2: Instance?
			cursor += 1

			if bit32.btest(flags_2, 2) then
				local player_3: Instance? = side[sideCursor]
				sideCursor += 1

				if typeof(player_3) ~= "Instance" then
					error("Slots[].taken.player: expected Instance")
				end

				player_2 = player_3
			end

			local taken_2 = { rig = rig, player = player_2 }
			taken = taken_2
		end

		local valueEntry = { slot = slot_2, taken = taken }
		value[index] = valueEntry
	end

	return runtime:deliver(5, player, cursor, sideCursor, value)
end

local function readDeath(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 7 > length then
		error("Death: truncated")
	end

	local character: number = buffer.readu16(packet, cursor)
	local body: number = buffer.readu16(packet, cursor + 2)
	local pushX: number = buffer.readi8(packet, cursor + 4)
	local pushY: number = buffer.readi8(packet, cursor + 5)
	local pushZ: number = buffer.readi8(packet, cursor + 6)
	cursor += 7

	return runtime:deliver(6, player, cursor, sideCursor, character, body, pushX, pushY, pushZ)
end

local function readPlatform(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 5 > length then
		error("Platform: truncated")
	end

	local platform: number = buffer.readu8(packet, cursor)

	if platform < 1 or platform > 127 then
		error("Platform.platform: out of range")
	end

	local tick: number = buffer.readu32(packet, cursor + 1)
	cursor += 5

	return runtime:deliver(7, player, cursor, sideCursor, platform, tick)
end

local function readGravity(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 12 > length then
		error("Gravity: truncated")
	end

	local gravity: number = buffer.readf64(packet, cursor)

	if gravity ~= gravity then
		error("Gravity.gravity: out of range")
	end

	local tick: number = buffer.readu32(packet, cursor + 8)
	cursor += 12

	return runtime:deliver(8, player, cursor, sideCursor, gravity, tick)
end

local function readSpectate(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Spectate: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local target: number?
	local tick: number = buffer.readu16(packet, cursor + 1)
	cursor += 3

	if bit32.btest(flags, 1) then
		if cursor + 2 > length then
			error("Spectate.target: truncated")
		end

		local target_2: number = buffer.readu16(packet, cursor)
		cursor += 2
		target = target_2
	end

	return runtime:deliver(9, player, cursor, sideCursor, target, tick)
end

local function readShared(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 8 > length then
		error("Shared: truncated")
	end

	local hash: number = buffer.readu32(packet, cursor)
	local tick: number = buffer.readu32(packet, cursor + 4)
	cursor += 8

	return runtime:deliver(10, player, cursor, sideCursor, hash, tick)
end

local function writeView(distance: number)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 2)

	if type(distance) ~= "number" or bit32.band(distance, 65535) ~= distance or distance < 1 then
		refuseReliable("View.distance: expected u16(1..65535)")
	end

	buffer.writeu16(out, offset + 1, distance)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x12E2915A,
	scope = "Tread",
	side = "client",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = true,
		maxOutgoing = 262144,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
		writeValidation = true,
	},

	messages = {
		[1] = { name = "Relay", kind = "event", mode = "SingleSync", queue = 64, read = readRelay },
		[2] = { name = "Withheld", kind = "event", mode = "SingleSync", queue = 64, read = readWithheld },
		[3] = { name = "Owner", kind = "event", mode = "SingleSync", queue = 64, read = readOwner },
		[4] = { name = "Feed", kind = "event", mode = "SingleSync", queue = 64, read = readFeed },
		[5] = { name = "Slots", kind = "event", mode = "SingleSync", queue = 64, read = readSlots },
		[6] = { name = "Death", kind = "event", mode = "SingleSync", queue = 64, read = readDeath },
		[7] = { name = "Platform", kind = "event", mode = "SingleSync", queue = 64, read = readPlatform },
		[8] = { name = "Gravity", kind = "event", mode = "SingleSync", queue = 64, read = readGravity },
		[9] = { name = "Spectate", kind = "event", mode = "SingleSync", queue = 64, read = readSpectate },
		[10] = { name = "Shared", kind = "event", mode = "SingleSync", queue = 64, read = readShared },
	},

	outgoing = {
		[1] = { name = "Move", kind = "event", reliable = false, minBytes = 9, maxBytes = 617 },
		[2] = { name = "View", kind = "event", reliable = true, minBytes = 3, maxBytes = 3 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
trimUnreliable = runtime.unreliable.trim
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Move = table.freeze({
		fire = function (command: number, acknowledged: number, received: number, delay: number, commands: { Command })
			if before[1] == nil or before[1](nil, command, acknowledged, received, delay, commands) then
				writeMove(command, acknowledged, received, delay, commands)
			end
		end,
	}) :: ClientEvent<(number, number, number, number, { Command })>,

	Relay = table.freeze({
		on = function (listener: (value: buffer) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, buffer)
			return runtime:iter(1)
		end,
	}) :: ClientListener<(buffer)>,

	Withheld = table.freeze({
		on = function (listener: (value: buffer) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, buffer)
			return runtime:iter(2)
		end,
	}) :: ClientListener<(buffer)>,

	Owner = table.freeze({
		on = function (listener: (value: buffer) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, buffer)
			return runtime:iter(3)
		end,
	}) :: ClientListener<(buffer)>,

	Feed = table.freeze({
		on = function (listener: (value: buffer) -> ()): () -> ()
			return runtime:on(4, listener)
		end,

		iter = function (): () -> (number, buffer)
			return runtime:iter(4)
		end,
	}) :: ClientListener<(buffer)>,

	Slots = table.freeze({
		on = function (listener: (value: { SlotEntry }) -> ()): () -> ()
			return runtime:on(5, listener)
		end,

		iter = function (): () -> (number, { SlotEntry })
			return runtime:iter(5)
		end,
	}) :: ClientListener<({ SlotEntry })>,

	Death = table.freeze({
		on = function (listener: (character: number, body: number, pushX: number, pushY: number, pushZ: number) -> ()): () -> ()
			return runtime:on(6, listener)
		end,

		iter = function (): () -> (number, number, number, number, number, number)
			return runtime:iter(6)
		end,
	}) :: ClientListener<(number, number, number, number, number)>,

	Platform = table.freeze({
		on = function (listener: (platform: number, tick: number) -> ()): () -> ()
			return runtime:on(7, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(7)
		end,
	}) :: ClientListener<(number, number)>,

	Gravity = table.freeze({
		on = function (listener: (gravity: number, tick: number) -> ()): () -> ()
			return runtime:on(8, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(8)
		end,
	}) :: ClientListener<(number, number)>,

	Spectate = table.freeze({
		on = function (listener: (target: number?, tick: number) -> ()): () -> ()
			return runtime:on(9, listener)
		end,

		iter = function (): () -> (number, number?, number)
			return runtime:iter(9)
		end,
	}) :: ClientListener<(number?, number)>,

	Shared = table.freeze({
		on = function (listener: (hash: number, tick: number) -> ()): () -> ()
			return runtime:on(10, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(10)
		end,
	}) :: ClientListener<(number, number)>,

	View = table.freeze({
		fire = function (distance: number)
			if before[2] == nil or before[2](nil, distance) then
				writeView(distance)
			end
		end,
	}) :: ClientEvent<(number)>,

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
	["Move"] = Network.Move,
	["Relay"] = Network.Relay,
	["Withheld"] = Network.Withheld,
	["Owner"] = Network.Owner,
	["Feed"] = Network.Feed,
	["Slots"] = Network.Slots,
	["Death"] = Network.Death,
	["Platform"] = Network.Platform,
	["Gravity"] = Network.Gravity,
	["Spectate"] = Network.Spectate,
	["Shared"] = Network.Shared,
	["View"] = Network.View,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
