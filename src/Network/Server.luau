--[[
    The server module Volt 0.1.0 generated from Tread.volt: a writer per
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
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local trimUnreliable: (number) -> ()
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()

local SLOTS_TAKEN_RIG: { "A" | "B" } = { "A", "B" }

local function readMove(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 8 > length then
		error("Move: truncated")
	end

	local command: number = buffer.readu16(packet, cursor)
	local acknowledged: number = buffer.readu16(packet, cursor + 2)
	local received: number = buffer.readu16(packet, cursor + 4)
	local delay: number = buffer.readu8(packet, cursor + 6)
	local commandsLength: number = buffer.readu8(packet, cursor + 7)

	if commandsLength > 8 then
		error("Move.commands: length out of range")
	end

	cursor += 8

	if cursor + 12 * commandsLength > length then
		error("Move.commands: truncated")
	end

	local commands: { Command } = table.create(commandsLength) :: { Command }

	for index = 1, commandsLength do
		if cursor + 12 > length then
			error("Move.commands: truncated")
		end

		local moveX: number = buffer.readi8(packet, cursor)

		if moveX < -127 then
			error("Move.commands[].moveX: out of range")
		end

		local moveZ: number = buffer.readi8(packet, cursor + 1)

		if moveZ < -127 then
			error("Move.commands[].moveZ: out of range")
		end

		local buttons: number = buffer.readu16(packet, cursor + 2)
		local yaw: number = buffer.readu16(packet, cursor + 4)
		local pitch: number = buffer.readi16(packet, cursor + 6)

		if pitch < -16384 or pitch > 16384 then
			error("Move.commands[].pitch: out of range")
		end

		local lean: number = buffer.readi8(packet, cursor + 8)

		if lean < -127 then
			error("Move.commands[].lean: out of range")
		end

		local headYaw: number = buffer.readi8(packet, cursor + 9)

		if headYaw < -127 then
			error("Move.commands[].headYaw: out of range")
		end

		local headPitch: number = buffer.readi8(packet, cursor + 10)

		if headPitch < -127 then
			error("Move.commands[].headPitch: out of range")
		end

		local fieldsLength: number = buffer.readu8(packet, cursor + 11)

		if fieldsLength > 64 then
			error("Move.commands[].fields: length out of range")
		end

		cursor += 12

		if cursor + fieldsLength > length then
			error("Move.commands[].fields: truncated")
		end

		local fields: buffer = buffer.create(fieldsLength)
		buffer.copy(fields, 0, packet, cursor, fieldsLength)

		cursor += fieldsLength
		local commandsEntry = { moveX = moveX, moveZ = moveZ, buttons = buttons, yaw = yaw, pitch = pitch, lean = lean, headYaw = headYaw, headPitch = headPitch, fields = fields }
		commands[index] = commandsEntry
	end

	return runtime:deliver(1, player, cursor, sideCursor, command, acknowledged, received, delay, commands)
end

local function writeRelay(value: buffer)
	local offset: number, out: buffer = beginUnreliable(899)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "buffer" then
		refuseUnreliable("Relay: expected buffer")
	end

	if buffer.len(value) > 896 then
		refuseUnreliable("Relay: length out of range")
	end

	buffer.writeu16(out, offset + 1, buffer.len(value))
	offset += 3
	buffer.copy(out, offset, value)
	offset += buffer.len(value)
	trimUnreliable(offset)
	markUnreliable()
end

local function writeWithheld(value: buffer)
	local offset: number, out: buffer = beginUnreliable(899)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "buffer" then
		refuseUnreliable("Withheld: expected buffer")
	end

	if buffer.len(value) > 896 then
		refuseUnreliable("Withheld: length out of range")
	end

	buffer.writeu16(out, offset + 1, buffer.len(value))
	offset += 3
	buffer.copy(out, offset, value)
	offset += buffer.len(value)
	trimUnreliable(offset)
	markUnreliable()
end

local function writeOwner(value: buffer)
	local offset: number, out: buffer = beginUnreliable(98)
	buffer.writeu8(out, offset, 3)

	if type(value) ~= "buffer" then
		refuseUnreliable("Owner: expected buffer")
	end

	if buffer.len(value) > 96 then
		refuseUnreliable("Owner: length out of range")
	end

	buffer.writeu8(out, offset + 1, buffer.len(value))
	offset += 2
	buffer.copy(out, offset, value)
	offset += buffer.len(value)
	trimUnreliable(offset)
	markUnreliable()
end

local function writeFeed(value: buffer)
	local offset: number, out: buffer = beginUnreliable(162)
	buffer.writeu8(out, offset, 4)

	if type(value) ~= "buffer" then
		refuseUnreliable("Feed: expected buffer")
	end

	if buffer.len(value) > 160 then
		refuseUnreliable("Feed: length out of range")
	end

	buffer.writeu8(out, offset + 1, buffer.len(value))
	offset += 2
	buffer.copy(out, offset, value)
	offset += buffer.len(value)
	trimUnreliable(offset)
	markUnreliable()
end

local function writeSlots(value: { SlotEntry })
	local offset: number, out: buffer = beginReliable(1022)
	buffer.writeu8(out, offset, 5)

	if type(value) ~= "table" then
		refuseReliable("Slots: expected table")
	end

	if #value > 255 then
		refuseReliable("Slots: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value)
	offset += 2

	for index = 1, #value do
		local flags: number = 0
		local valueEntry = value[index]

		if type(valueEntry) ~= "table" then
			refuseReliable("Slots[]: expected table")
		end

		local slot_2 = valueEntry.slot

		if type(slot_2) ~= "number" or bit32.band(slot_2, 65535) ~= slot_2 then
			refuseReliable("Slots[].slot: expected u16")
		end

		buffer.writeu16(out, offset + 1, slot_2)
		local taken = valueEntry.taken
		flags += taken ~= nil and 1 or 0
		buffer.writeu8(out, offset, flags)
		offset += 3

		if taken ~= nil then
			local flags_2: number = 0

			if type(taken) ~= "table" then
				refuseReliable("Slots[].taken: expected table")
			end

			local rig = taken.rig
			local rigIndex: number = table.find(SLOTS_TAKEN_RIG, rig) or 0

			if rigIndex == 0 then
				refuseReliable("Slots[].taken.rig: expected enum { A, B }")
			end

			flags_2 += rigIndex - 1
			local player_2 = taken.player
			flags_2 += player_2 ~= nil and 2 or 0
			buffer.writeu8(out, offset, flags_2)
			offset += 1

			if player_2 ~= nil then
				if typeof(player_2) ~= "Instance" then
					refuseReliable("Slots[].taken.player: expected Instance")
				end

				slotReliable(player_2)
			end
		end
	end

	trimReliable(offset)
end

local function writeDeath(character: number, body: number, pushX: number, pushY: number, pushZ: number)
	local offset: number, out: buffer = beginReliable(8)
	buffer.writeu8(out, offset, 6)

	if type(character) ~= "number" or bit32.band(character, 65535) ~= character then
		refuseReliable("Death.character: expected u16")
	end

	buffer.writeu16(out, offset + 1, character)

	if type(body) ~= "number" or bit32.band(body, 65535) ~= body then
		refuseReliable("Death.body: expected u16")
	end

	buffer.writeu16(out, offset + 3, body)

	if type(pushX) ~= "number" or pushX % 1 ~= 0 or pushX < -128 or pushX > 127 then
		refuseReliable("Death.pushX: expected i8")
	end

	buffer.writei8(out, offset + 5, pushX)

	if type(pushY) ~= "number" or pushY % 1 ~= 0 or pushY < -128 or pushY > 127 then
		refuseReliable("Death.pushY: expected i8")
	end

	buffer.writei8(out, offset + 6, pushY)

	if type(pushZ) ~= "number" or pushZ % 1 ~= 0 or pushZ < -128 or pushZ > 127 then
		refuseReliable("Death.pushZ: expected i8")
	end

	buffer.writei8(out, offset + 7, pushZ)
end

local function writePlatform(platform: number, tick: number)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 7)

	if type(platform) ~= "number" or bit32.band(platform, 255) ~= platform or platform < 1 or platform > 127 then
		refuseReliable("Platform.platform: expected u8(1..127)")
	end

	buffer.writeu8(out, offset + 1, platform)

	if type(tick) ~= "number" or bit32.band(tick, 4294967295) ~= tick then
		refuseReliable("Platform.tick: expected u32")
	end

	buffer.writeu32(out, offset + 2, tick)
end

local function writeSpectate(target: number?, tick: number)
	local offset: number, out: buffer = beginReliable(6)
	buffer.writeu8(out, offset, 8)
	local flags: number = 0
	flags += target ~= nil and 1 or 0

	if type(tick) ~= "number" or bit32.band(tick, 65535) ~= tick then
		refuseReliable("Spectate.tick: expected u16")
	end

	buffer.writeu16(out, offset + 2, tick)
	buffer.writeu8(out, offset + 1, flags)
	offset += 4

	if target ~= nil then
		if type(target) ~= "number" or bit32.band(target, 65535) ~= target then
			refuseReliable("Spectate.target: expected u16")
		end

		buffer.writeu16(out, offset, target)
		offset += 2
	end

	trimReliable(offset)
end

local function writeShared(hash: number, tick: number)
	local offset: number, out: buffer = beginReliable(9)
	buffer.writeu8(out, offset, 9)

	if type(hash) ~= "number" or bit32.band(hash, 4294967295) ~= hash then
		refuseReliable("Shared.hash: expected u32")
	end

	buffer.writeu32(out, offset + 1, hash)

	if type(tick) ~= "number" or bit32.band(tick, 4294967295) ~= tick then
		refuseReliable("Shared.tick: expected u32")
	end

	buffer.writeu32(out, offset + 5, tick)
end

local function readView(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("View: truncated")
	end

	local distance: number = buffer.readu16(packet, cursor)

	if distance < 1 then
		error("View.distance: out of range")
	end

	cursor += 2

	return runtime:deliver(2, player, cursor, sideCursor, distance)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x9814AF4F,
	scope = "Tread",
	side = "server",
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
		[1] = { name = "Move", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readMove },
		[2] = { name = "View", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readView },
	},

	outgoing = {
		[1] = { name = "Relay", kind = "event", reliable = false, minBytes = 3, maxBytes = 899 },
		[2] = { name = "Withheld", kind = "event", reliable = false, minBytes = 3, maxBytes = 899 },
		[3] = { name = "Owner", kind = "event", reliable = false, minBytes = 2, maxBytes = 98 },
		[4] = { name = "Feed", kind = "event", reliable = false, minBytes = 2, maxBytes = 162 },
		[5] = { name = "Slots", kind = "event", reliable = true, minBytes = 2, maxBytes = 1022 },
		[6] = { name = "Death", kind = "event", reliable = true, minBytes = 8, maxBytes = 8 },
		[7] = { name = "Platform", kind = "event", reliable = true, minBytes = 6, maxBytes = 6 },
		[8] = { name = "Spectate", kind = "event", reliable = true, minBytes = 4, maxBytes = 6 },
		[9] = { name = "Shared", kind = "event", reliable = true, minBytes = 9, maxBytes = 9 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
trimUnreliable = runtime.unreliable.trim
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Move = table.freeze({
		on = function (listener: (player: Player | Bot, command: number, acknowledged: number, received: number, delay: number, commands: { Command }) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number, number, number, number, { Command })
			return runtime:iter(1)
		end,
	}) :: ServerListener<(number, number, number, number, { Command })>,

	Relay = table.freeze({
		fire = function (player: Player | Bot, value: buffer)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player) then
				writeRelay(value)
			end
		end,

		fireAll = function (value: buffer)
			runtime:broadcast(1, nil, nil, writeRelay, value)
		end,

		fireList = function (players: { Player | Bot }, value: buffer)
			runtime:broadcast(1, players, nil, writeRelay, value)
		end,

		fireExcept = function (player: Player | Bot, value: buffer)
			runtime:broadcast(1, nil, player, writeRelay, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: buffer)
			runtime:broadcast(1, players, nil, writeRelay, value)
		end,
	}) :: ServerEvent<(buffer)>,

	Withheld = table.freeze({
		fire = function (player: Player | Bot, value: buffer)
			if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
				writeWithheld(value)
			end
		end,

		fireAll = function (value: buffer)
			runtime:broadcast(2, nil, nil, writeWithheld, value)
		end,

		fireList = function (players: { Player | Bot }, value: buffer)
			runtime:broadcast(2, players, nil, writeWithheld, value)
		end,

		fireExcept = function (player: Player | Bot, value: buffer)
			runtime:broadcast(2, nil, player, writeWithheld, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: buffer)
			runtime:broadcast(2, players, nil, writeWithheld, value)
		end,
	}) :: ServerEvent<(buffer)>,

	Owner = table.freeze({
		fire = function (player: Player | Bot, value: buffer)
			if (before[3] == nil or before[3](player, value)) and runtime:target(player) then
				writeOwner(value)
			end
		end,

		fireAll = function (value: buffer)
			runtime:broadcast(3, nil, nil, writeOwner, value)
		end,

		fireList = function (players: { Player | Bot }, value: buffer)
			runtime:broadcast(3, players, nil, writeOwner, value)
		end,

		fireExcept = function (player: Player | Bot, value: buffer)
			runtime:broadcast(3, nil, player, writeOwner, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: buffer)
			runtime:broadcast(3, players, nil, writeOwner, value)
		end,
	}) :: ServerEvent<(buffer)>,

	Feed = table.freeze({
		fire = function (player: Player | Bot, value: buffer)
			if (before[4] == nil or before[4](player, value)) and runtime:target(player) then
				writeFeed(value)
			end
		end,

		fireAll = function (value: buffer)
			runtime:broadcast(4, nil, nil, writeFeed, value)
		end,

		fireList = function (players: { Player | Bot }, value: buffer)
			runtime:broadcast(4, players, nil, writeFeed, value)
		end,

		fireExcept = function (player: Player | Bot, value: buffer)
			runtime:broadcast(4, nil, player, writeFeed, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: buffer)
			runtime:broadcast(4, players, nil, writeFeed, value)
		end,
	}) :: ServerEvent<(buffer)>,

	Slots = table.freeze({
		fire = function (player: Player | Bot, value: { SlotEntry })
			if (before[5] == nil or before[5](player, value)) and runtime:target(player) then
				writeSlots(value)
			end
		end,

		fireAll = function (value: { SlotEntry })
			runtime:broadcast(5, nil, nil, writeSlots, value)
		end,

		fireList = function (players: { Player | Bot }, value: { SlotEntry })
			runtime:broadcast(5, players, nil, writeSlots, value)
		end,

		fireExcept = function (player: Player | Bot, value: { SlotEntry })
			runtime:broadcast(5, nil, player, writeSlots, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: { SlotEntry })
			runtime:broadcast(5, players, nil, writeSlots, value)
		end,
	}) :: ServerEvent<({ SlotEntry })>,

	Death = table.freeze({
		fire = function (player: Player | Bot, character: number, body: number, pushX: number, pushY: number, pushZ: number)
			if (before[6] == nil or before[6](player, character, body, pushX, pushY, pushZ)) and runtime:target(player) then
				writeDeath(character, body, pushX, pushY, pushZ)
			end
		end,

		fireAll = function (character: number, body: number, pushX: number, pushY: number, pushZ: number)
			runtime:broadcast(6, nil, nil, writeDeath, character, body, pushX, pushY, pushZ)
		end,

		fireList = function (players: { Player | Bot }, character: number, body: number, pushX: number, pushY: number, pushZ: number)
			runtime:broadcast(6, players, nil, writeDeath, character, body, pushX, pushY, pushZ)
		end,

		fireExcept = function (player: Player | Bot, character: number, body: number, pushX: number, pushY: number, pushZ: number)
			runtime:broadcast(6, nil, player, writeDeath, character, body, pushX, pushY, pushZ)
		end,

		fireSet = function (players: { [Player | Bot]: true }, character: number, body: number, pushX: number, pushY: number, pushZ: number)
			runtime:broadcast(6, players, nil, writeDeath, character, body, pushX, pushY, pushZ)
		end,
	}) :: ServerEvent<(number, number, number, number, number)>,

	Platform = table.freeze({
		fire = function (player: Player | Bot, platform: number, tick: number)
			if (before[7] == nil or before[7](player, platform, tick)) and runtime:target(player) then
				writePlatform(platform, tick)
			end
		end,

		fireAll = function (platform: number, tick: number)
			runtime:broadcast(7, nil, nil, writePlatform, platform, tick)
		end,

		fireList = function (players: { Player | Bot }, platform: number, tick: number)
			runtime:broadcast(7, players, nil, writePlatform, platform, tick)
		end,

		fireExcept = function (player: Player | Bot, platform: number, tick: number)
			runtime:broadcast(7, nil, player, writePlatform, platform, tick)
		end,

		fireSet = function (players: { [Player | Bot]: true }, platform: number, tick: number)
			runtime:broadcast(7, players, nil, writePlatform, platform, tick)
		end,
	}) :: ServerEvent<(number, number)>,

	Spectate = table.freeze({
		fire = function (player: Player | Bot, target: number?, tick: number)
			if (before[8] == nil or before[8](player, target, tick)) and runtime:target(player) then
				writeSpectate(target, tick)
			end
		end,

		fireAll = function (target: number?, tick: number)
			runtime:broadcast(8, nil, nil, writeSpectate, target, tick)
		end,

		fireList = function (players: { Player | Bot }, target: number?, tick: number)
			runtime:broadcast(8, players, nil, writeSpectate, target, tick)
		end,

		fireExcept = function (player: Player | Bot, target: number?, tick: number)
			runtime:broadcast(8, nil, player, writeSpectate, target, tick)
		end,

		fireSet = function (players: { [Player | Bot]: true }, target: number?, tick: number)
			runtime:broadcast(8, players, nil, writeSpectate, target, tick)
		end,
	}) :: ServerEvent<(number?, number)>,

	Shared = table.freeze({
		fire = function (player: Player | Bot, hash: number, tick: number)
			if (before[9] == nil or before[9](player, hash, tick)) and runtime:target(player) then
				writeShared(hash, tick)
			end
		end,

		fireAll = function (hash: number, tick: number)
			runtime:broadcast(9, nil, nil, writeShared, hash, tick)
		end,

		fireList = function (players: { Player | Bot }, hash: number, tick: number)
			runtime:broadcast(9, players, nil, writeShared, hash, tick)
		end,

		fireExcept = function (player: Player | Bot, hash: number, tick: number)
			runtime:broadcast(9, nil, player, writeShared, hash, tick)
		end,

		fireSet = function (players: { [Player | Bot]: true }, hash: number, tick: number)
			runtime:broadcast(9, players, nil, writeShared, hash, tick)
		end,
	}) :: ServerEvent<(number, number)>,

	View = table.freeze({
		on = function (listener: (player: Player | Bot, distance: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number)
			return runtime:iter(2)
		end,
	}) :: ServerListener<(number)>,

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
	["Move"] = Network.Move,
	["Relay"] = Network.Relay,
	["Withheld"] = Network.Withheld,
	["Owner"] = Network.Owner,
	["Feed"] = Network.Feed,
	["Slots"] = Network.Slots,
	["Death"] = Network.Death,
	["Platform"] = Network.Platform,
	["Spectate"] = Network.Spectate,
	["Shared"] = Network.Shared,
	["View"] = Network.View,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
