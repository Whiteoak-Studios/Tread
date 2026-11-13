--[[
    A target nobody watches sends no feed and keeps none of its stepped
    looks, before its first watcher and after its last one leaves, so the
    next watch's first feed carries only what was stepped since
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local ID: number = 4097
local STEPPED: number = 3
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
	local command: { [string]: any } = Command.new()

	-- Nobody watches yet: what it steps is dropped, and a feed sends nothing
	for _ = 1, STEPPED do
		Spectate.stepped(target, command)
	end

	Spectate.feed(target, owner, length)
	if #feeds ~= 0 or Spectate.watchers(target) ~= nil then
		return false, "A target nobody watches sent a feed or gained a watchers list"
	end

	local read: any = Feed.new()
	Spectate.watch(moderator, target, ID, 0)
	Spectate.feed(target, owner, length)
	Feed.read(feeds[1], read, Game.limits)
	if #feeds ~= 1 or read.count ~= 0 then
		return false, `The first feed carried {read.count} looks stepped before anyone watched`
	end

	-- The last watcher leaves with looks kept, and they go with it
	for _ = 1, STEPPED do
		Spectate.stepped(target, command)
	end

	Spectate.unwatch(moderator, 1)
	Spectate.feed(target, owner, length)
	if #feeds ~= 1 then
		return false, "A target whose last watcher left still sent a feed"
	end

	Spectate.watch(moderator, target, ID, 2)
	Spectate.feed(target, owner, length)
	Feed.read(feeds[2], read, Game.limits)
	if read.count ~= 0 then
		return false, `A target watched again sent {read.count} looks stepped while its last watcher was there`
	end

	return true, nil
end
