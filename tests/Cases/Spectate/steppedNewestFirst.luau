--[[
    A watched target keeps the look of each command it steps, copied from
    the table the server reuses, newest first and at most a Move's 8, and
    its feed carries them once and then none
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local YAW_STEP: number = 2 * math.pi / 65536 -- A feed look's yaw step, Move's
local PITCH_STEP: number = (math.pi / 2) / 16384
local HEAD_STEP: number = 75 / 127 -- The head offset's step at the fixture's 75° cone
local STEPPED: number = 11 -- More commands than one feed carries
local CAP: number = 8 -- A Move's commands, the most looks a feed carries
local LATER: number = 3 -- Commands stepped after the first feed
local LATER_BASE: number = 100 -- Where the later commands' yaw steps count from
local CLOSE: number = 1e-9
local ID: number = 4097
local OWNER_BYTES: number = 91 -- The longest OwnerState, room for any

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Command: any = globals.require(tread.Codec.Command)
	local Feed: any = globals.require(tread.Codec.Feed)
	local Fields: any = globals.require(tread.Codec.Fields)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Spectate: any = globals.require(tread.Server.Spectate)
	local State: any = globals.require(tread.Step.State)

	-- Each feed sent, copied, since Volt copies the pooled buffer before its fire returns
	local feeds: { buffer } = {}
	Spectate.start({
		limits = Game.limits,
		sendFeed = function (_: { any }, data: buffer)
			local copy: buffer = buffer.create(buffer.len(data))
			buffer.copy(copy, 0, data)
			table.insert(feeds, copy)
		end,
		sendSpectate = function (_: any, _: number?, _: number) end,
	})

	local layout: any = Fields.compile({ command = {}, rules = {}, server = {}, slot = {}, held = {} })
	local owner: buffer = buffer.create(OWNER_BYTES)
	local length: number = OwnerState.write(State.new(), owner, 0, layout, Game.limits)

	local moderator: any = roblox.Instance.new("Player")
	local target: any = roblox.Instance.new("Player")
	Spectate.watch(moderator, target, ID, 0)

	-- The one command table the server reuses, its yaw counting the commands and its other parts each a step apart
	local command: { [string]: any } = Command.new()
	for index: number = 1, STEPPED do
		command.yaw = index * YAW_STEP
		command.pitch = -index * PITCH_STEP
		command.headYaw = index * HEAD_STEP
		command.headPitch = -index * HEAD_STEP
		Spectate.stepped(target, command)
	end

	Spectate.feed(target, owner, length)

	local read: any = Feed.new()
	Feed.read(feeds[1], read, Game.limits)
	if read.count ~= CAP then
		return false, `After {STEPPED} stepped commands the feed carried {read.count} looks, not {CAP}`
	end

	for place: number = 1, CAP do
		local index: number = STEPPED + 1 - place
		local look: { [string]: number } = read.looks[place]
		if
			math.abs(look.yaw - index * YAW_STEP) > CLOSE
			or math.abs(look.pitch + index * PITCH_STEP) > CLOSE
			or math.abs(look.headYaw - index * HEAD_STEP) > CLOSE
			or math.abs(look.headPitch + index * HEAD_STEP) > CLOSE
		then
			return false, `The feed's look {place} is not command {index}'s, so the looks aren't newest first`
		end
	end

	-- Only what was stepped since the last feed goes in the next one
	for index: number = 1, LATER do
		command.yaw = (LATER_BASE + index) * YAW_STEP
		Spectate.stepped(target, command)
	end

	Spectate.feed(target, owner, length)
	Feed.read(feeds[2], read, Game.limits)
	if read.count ~= LATER then
		return false, `The second feed carried {read.count} looks, not the {LATER} stepped since the first`
	end

	for place: number = 1, LATER do
		if math.abs(read.looks[place].yaw - (LATER_BASE + LATER + 1 - place) * YAW_STEP) > CLOSE then
			return false, `The second feed's look {place} is not the right later command's`
		end
	end

	Spectate.feed(target, owner, length)
	Feed.read(feeds[3], read, Game.limits)
	if read.count ~= 0 or #feeds ~= 3 then
		return false, `A feed with nothing stepped since the last carried {read.count} looks`
	end

	return true, nil
end
