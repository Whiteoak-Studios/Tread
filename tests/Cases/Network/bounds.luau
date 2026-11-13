--[[
    The generated writers hold each bounded endpoint to the bound the design
    gives it: a value at the bound is sent, and one past it is refused
--]]

--!strict
local Environment = require("../../Environment")

local SERVER: string = "src/Network/Server.luau"
local CLIENT: string = "src/Network/Client.luau"
local COMMANDS: number = 8 -- The most a Move carries
local FIELDS: number = 64 -- The most bytes of game fields a command carries
local PITCH: number = 16384 -- A command's pitch at 90°
local STEPS: number = 127 -- An i8 lean's or head offset's steps to its limit either way
local BLOCK: number = 896 -- A relay or withheld block's bytes
local OWNER: number = 96
local FEED: number = 160
local SLOT_ENTRIES: number = 255
local PLATFORM: number = 127 -- The highest platform id, from 1
local TICK: number = 0

type Send = { name: string, send: (...any) -> (), arguments: { any }, sent: boolean }

-- One of Tread's own command fields set to a value, the rest at zero, with that many bytes of game fields
local function command(field: string, value: number, fields: number): { [string]: any }
	local made: { [string]: any } = {
		moveX = 0,
		moveZ = 0,
		buttons = 0,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = buffer.create(fields),
	}
	made[field] = value

	return made
end

local function commands(count: number, fields: number): { { [string]: any } }
	local made: { { [string]: any } } = {}

	for _ = 1, count do
		table.insert(made, command("buttons", 0, fields))
	end

	return made
end

local function entries(count: number): { { [string]: any } }
	local made: { { [string]: any } } = {}

	for slot: number = 1, count do
		table.insert(made, { slot = slot })
	end

	return made
end

return function (): (boolean, string | nil)
	local server: any = Environment.load(SERVER)
	local client: any = Environment.load(CLIENT)

	local move: (...any) -> () = client.Move.fire

	local sends: { Send } = {
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, commands(COMMANDS, FIELDS) }, sent = true },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, commands(COMMANDS + 1, 0) }, sent = false },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, commands(1, FIELDS + 1) }, sent = false },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, { command("pitch", -PITCH, 0) } }, sent = true },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, { command("pitch", PITCH + 1, 0) } }, sent = false },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, { command("headYaw", -STEPS, 0) } }, sent = true },
		{ name = "Move", send = move, arguments = { 0, 0, 0, 0, { command("lean", -STEPS - 1, 0) } }, sent = false },
		{ name = "Relay", send = server.Relay.fireAll, arguments = { buffer.create(BLOCK) }, sent = true },
		{ name = "Relay", send = server.Relay.fireAll, arguments = { buffer.create(BLOCK + 1) }, sent = false },
		{ name = "Withheld", send = server.Withheld.fireAll, arguments = { buffer.create(BLOCK) }, sent = true },
		{ name = "Withheld", send = server.Withheld.fireAll, arguments = { buffer.create(BLOCK + 1) }, sent = false },
		{ name = "Owner", send = server.Owner.fireAll, arguments = { buffer.create(OWNER) }, sent = true },
		{ name = "Owner", send = server.Owner.fireAll, arguments = { buffer.create(OWNER + 1) }, sent = false },
		{ name = "Feed", send = server.Feed.fireAll, arguments = { buffer.create(FEED) }, sent = true },
		{ name = "Feed", send = server.Feed.fireAll, arguments = { buffer.create(FEED + 1) }, sent = false },
		{ name = "Slots", send = server.Slots.fireAll, arguments = { entries(SLOT_ENTRIES) }, sent = true },
		{ name = "Slots", send = server.Slots.fireAll, arguments = { entries(SLOT_ENTRIES + 1) }, sent = false },
		{ name = "Platform", send = server.Platform.fireAll, arguments = { 1, TICK }, sent = true },
		{ name = "Platform", send = server.Platform.fireAll, arguments = { PLATFORM, TICK }, sent = true },
		{ name = "Platform", send = server.Platform.fireAll, arguments = { 0, TICK }, sent = false },
		{ name = "Platform", send = server.Platform.fireAll, arguments = { PLATFORM + 1, TICK }, sent = false },
	}

	for index: number, row: Send in sends do
		local sent: boolean, message: any = pcall(row.send, table.unpack(row.arguments))

		if sent ~= row.sent then
			local outcome: string = sent and "sent" or `refused ({message})`
			return false, `{row.name} send {index} was {outcome}, where its bound has it the other way`
		end

		-- A refusal must be the endpoint's own writer's, never some other error
		if not sent and string.find(`{message}`, row.name, 1, true) ~= 1 then
			return false, `{row.name} send {index} failed with something other than its writer's refusal: {message}`
		end
	end

	return true, nil
end
