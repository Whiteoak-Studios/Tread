--[[
    The moderator's feed carries the target's OwnerState byte for byte and
    the look of up to 8 stepped commands at Move's precision, at most 142 B,
    and refuses more looks, a longer OwnerState and bytes that aren't a feed
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local YAW_STEP: number = 2 * math.pi / 65536
local PITCH_STEP: number = (math.pi / 2) / 16384
local CLOSE: number = 1e-9
local WORD: number = 2 ^ 32 - 1

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Command: any = globals.require(tread.Codec.Command)
	local Feed: any = globals.require(tread.Codec.Feed)
	local Fields: any = globals.require(tread.Codec.Fields)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local State: any = globals.require(tread.Step.State)

	-- The largest OwnerState, both game blocks at their bounds
	local largest: any = Fields.compile(Game.largest)
	local state: { [string]: any } = State.new()
	state.fields, state.block = {}, {}
	for _, field: { [string]: any } in Game.largest.server do
		state.fields[field.name] = WORD
	end

	for _, field: { [string]: any } in Game.largest.rules do
		state.block[field.name] = WORD
	end

	local owner: buffer = buffer.create(96)
	local ownerLength: number = OwnerState.write(state, owner, 2, largest, Game.limits)

	-- Eight looks at their edges and steps
	local looks: { { number } } = {
		{ 0, math.pi / 2, 75, -75 },
		{ 2 * math.pi - YAW_STEP, -math.pi / 2, -75, 75 },
		{ YAW_STEP, PITCH_STEP, 75 / 127, -75 / 127 },
		{ math.pi, -PITCH_STEP, 0, 0 },
		{ 1, 0.5, 10, 20 },
		{ 2, -0.5, -10, -20 },
		{ 3, 1, 30, -30 },
		{ 4, -1, -30, 30 },
	}

	local commands: { { [string]: any } } = {}
	for _, look: { number } in looks do
		local command: { [string]: any } = Command.new()
		command.yaw, command.pitch, command.headYaw, command.headPitch = look[1], look[2], look[3], look[4]
		table.insert(commands, command)
	end

	local data: buffer = buffer.create(160)
	local bytes: number = Feed.write(data, owner, 2, ownerLength, commands, 8, Game.limits)
	if ownerLength ~= 92 or bytes ~= 142 then
		return false, `The largest feed filled {bytes} B around {ownerLength} B of OwnerState, not 142 around 92`
	end

	local exact: buffer = buffer.create(bytes)
	buffer.copy(exact, 0, data, 0, bytes)

	local feed: any = Feed.new()
	Feed.read(exact, feed, Game.limits)
	if feed.count ~= 8 or feed.ownerLength ~= 92 then
		return false, `The feed read back {feed.count} looks and {feed.ownerLength} B of OwnerState`
	end

	for index: number = 0, 91 do
		if buffer.readu8(exact, feed.ownerAt + index) ~= buffer.readu8(owner, 2 + index) then
			return false, `The feed's OwnerState differs from the target's at byte {index}`
		end
	end

	for index: number, look: { number } in looks do
		local back: { [string]: number } = feed.looks[index]
		local read: { number } = { back.yaw, back.pitch, back.headYaw, back.headPitch }

		for part: number = 1, 4 do
			-- Each look reads back at its step, so writing it again gives the same bytes
			local step: number = ({ YAW_STEP, PITCH_STEP, 75 / 127, 75 / 127 })[part]
			if math.abs(read[part] - look[part]) > step / 2 + CLOSE then
				return false, `Look {index} part {part} read back {read[part]}, not within a step of {look[part]}`
			end
		end
	end

	-- A feed of no looks around an empty OwnerState is the two counts alone
	if Feed.write(data, owner, 0, 0, commands, 0, Game.limits) ~= 2 then
		return false, "An empty feed filled other than its two counts"
	end

	local refused: boolean, why: string =
		Refuses("at most 92 B", Feed.write, data, owner, 0, 93, commands, 0, Game.limits)
	if not refused then
		return false, `A feed around 93 B of OwnerState was written: {why}`
	end

	table.insert(commands, Command.new())
	refused, why = Refuses("8 looks", Feed.write, data, owner, 0, 0, commands, 9, Game.limits)
	if not refused then
		return false, `A feed of 9 looks was written: {why}`
	end

	refused, why =
		Refuses("passes its 100 B", Feed.write, buffer.create(100), owner, 2, ownerLength, commands, 8, Game.limits)
	if not refused then
		return false, `A feed past its buffer was written: {why}`
	end

	-- Bytes that aren't a feed
	local cut: buffer = buffer.create(bytes - 1)
	buffer.copy(cut, 0, exact, 0, bytes - 1)
	refused, why = Refuses("don't end", Feed.read, cut, Feed.new(), Game.limits)
	if not refused then
		return false, `A feed cut short was read: {why}`
	end

	refused, why = Refuses("passes", Feed.read, buffer.fromstring("\200\0"), Feed.new(), Game.limits)
	if not refused then
		return false, `A feed whose OwnerState passes its end was read: {why}`
	end

	refused, why = Refuses("at least 2 B", Feed.read, buffer.create(1), Feed.new(), Game.limits)
	if not refused then
		return false, `A feed of 1 B was read: {why}`
	end

	return true, nil
end
