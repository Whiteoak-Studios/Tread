--[[
    A feed goes once to the target's own watchers list, a player and a bot,
    in a buffer of its exact length reused for that length, and Feed.read
    gives back the target's OwnerState byte for byte and its stepped looks
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local YAW_STEP: number = 2 * math.pi / 65536
local PITCH_STEP: number = (math.pi / 2) / 16384
local HEAD_STEP: number = 75 / 127
local SPARE: number = 7 -- Bytes the target's buffer holds past its OwnerState, which the feed leaves out
local CLOSE: number = 1e-9
local ID: number = 4097

-- Two stepped commands' looks on their steps, oldest first: yaw, pitch, head yaw and head pitch
local LOOKS: { { number } } = {
	{ 12345 * YAW_STEP, -4321 * PITCH_STEP, 127 * HEAD_STEP, -127 * HEAD_STEP },
	{ 65535 * YAW_STEP, 16384 * PITCH_STEP, -50 * HEAD_STEP, 0 },
}

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Command: any = globals.require(tread.Codec.Command)
	local Feed: any = globals.require(tread.Codec.Feed)
	local Fields: any = globals.require(tread.Codec.Fields)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Spectate: any = globals.require(tread.Server.Spectate)
	local State: any = globals.require(tread.Step.State)

	-- Each feed as the keys and buffer it was handed, and a copy of its bytes
	local keys: { { any } } = {}
	local buffers: { buffer } = {}
	local copies: { buffer } = {}
	Spectate.start({
		limits = Game.limits,
		sendFeed = function (to: { any }, data: buffer)
			local copy: buffer = buffer.create(buffer.len(data))
			buffer.copy(copy, 0, data)
			table.insert(keys, to)
			table.insert(buffers, data)
			table.insert(copies, copy)
		end,
		sendSpectate = function (_: any, _: number?, _: number) end,
	})

	-- The target's OwnerState with both game blocks set, at a place and speed on their steps
	local layout: any = Fields.compile(Game.fields)
	local state: { [string]: any } = State.new()
	state.position = vector.create(100.5, -3.25, 4000 + 1 / 512)
	state.velocity = vector.create(12.5, -40, 1 / 64)
	state.fields = Game.high.server
	state.block = Game.high.rules

	local owner: buffer = buffer.create(100)
	local length: number = OwnerState.write(state, owner, 0, layout, Game.limits)
	local held: buffer = buffer.create(length + SPARE)
	buffer.copy(held, 0, owner, 0, length)
	buffer.fill(held, length, 255, SPARE)

	local player: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }
	local target: any = roblox.Instance.new("Player")
	Spectate.watch(player, target, ID, 0)
	Spectate.watch(bot, target, ID, 0)

	local command: { [string]: any } = Command.new()
	for _, look: { number } in LOOKS do
		command.yaw, command.pitch, command.headYaw, command.headPitch = look[1], look[2], look[3], look[4]
		Spectate.stepped(target, command)
	end

	Spectate.feed(target, held, length)
	if #keys ~= 1 or keys[1] ~= Spectate.watchers(target) or #keys[1] ~= 2 then
		return false, "The feed did not go once, to the target's own watchers list of the player and the bot"
	elseif buffer.len(buffers[1]) ~= 2 + length + #LOOKS * 6 then
		return false, `The feed's buffer is {buffer.len(buffers[1])} B, not its exact {2 + length + #LOOKS * 6}`
	end

	local read: any = Feed.new()
	Feed.read(copies[1], read, Game.limits)
	if read.ownerLength ~= length or read.count ~= #LOOKS then
		return false, `The feed read back {read.ownerLength} B of OwnerState and {read.count} looks`
	end

	for index: number = 0, length - 1 do
		if buffer.readu8(read.ownerData, read.ownerAt + index) ~= buffer.readu8(owner, index) then
			return false, `The feed's OwnerState differs from the target's at byte {index}`
		end
	end

	-- The bytes decode as the target's state too
	local into: { [string]: any } = State.new()
	OwnerState.read(read.ownerData, read.ownerAt, read.ownerLength, into, layout, Game.limits)
	if into.position ~= state.position or into.fields.reviver ~= Game.high.server.reviver then
		return false, "The feed's OwnerState decodes to another state than the target's"
	end

	for place: number = 1, #LOOKS do
		local look: { number } = LOOKS[#LOOKS + 1 - place]
		local back: { [string]: number } = read.looks[place]
		local parts: { number } = { back.yaw, back.pitch, back.headYaw, back.headPitch }

		for part: number = 1, 4 do
			if math.abs(parts[part] - look[part]) > CLOSE then
				return false, `The feed's look {place} part {part} read back {parts[part]}, not {look[part]}`
			end
		end
	end

	-- A feed of the same length goes in the same buffer
	for _, look: { number } in LOOKS do
		command.yaw, command.pitch, command.headYaw, command.headPitch = look[1], look[2], look[3], look[4]
		Spectate.stepped(target, command)
	end

	Spectate.feed(target, held, length)
	if #buffers ~= 2 or buffers[2] ~= buffers[1] then
		return false, "A second feed of the same length did not reuse the first one's buffer"
	elseif buffer.tostring(copies[2]) ~= buffer.tostring(copies[1]) then
		return false, "The same state and looks gave a second feed of other bytes"
	end

	return true, nil
end
