--[[
    server:spectate refuses a moderator with no character, a target that is
    no live character, and a target's 32nd watcher, while its 31st and a
    watcher's repeat are taken; spectatorsOf names the Players watching a
    player, and viewersOf adds each viewer's spectators to its viewers
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3
local WATCHERS: number = 31 -- The most one target takes
local PING: number = 0.05 -- Seconds each Lune player's engine ping reports
local ROW: number = 3 -- Studs between the watchers' characters

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()

	local target: any = server:create(rig.mock:addBot("Target"), rig:at(6, 0))

	if pcall(server.spectate, server, rig.mock:addBot("Bodiless"), target) then
		return false, "server:spectate took a moderator with no character"
	end

	local moderators: { any } = {}
	for index: number = 1, WATCHERS + 1 do
		local bot: any = rig.mock:addBot(`Moderator{index}`)
		server:create(bot, rig:at(-20 + index % 10 * ROW, -20 + index // 10 * ROW))
		table.insert(moderators, bot)
	end

	if pcall(server.spectate, server, moderators[1], "Target") then
		return false, "server:spectate took a string for its target"
	end

	for index: number = 1, WATCHERS do
		server:spectate(moderators[index], target)
	end

	-- A watcher spectating its target again keeps its place
	server:spectate(moderators[WATCHERS], target)

	local refused: boolean, message: any = pcall(server.spectate, server, moderators[WATCHERS + 1], target)
	if refused then
		return false, "server:spectate took a target's 32nd watcher"
	elseif not string.find(tostring(message), `{WATCHERS} watchers`, 1, true) then
		return false, `The 32nd watcher's refusal named no limit: {message}`
	end

	for index: number = 1, WATCHERS do
		server:spectate(moderators[index], nil)
	end

	-- A Player moderator watching a Player viewer sees what the viewer is sent
	local viewer: any = roblox.Instance.new("Player")
	local moderator: any = roblox.Instance.new("Player")
	Pings[viewer] = PING
	Pings[moderator] = PING

	local seen: any = server:create(viewer, rig:at(3, 0))
	server:create(moderator, rig:at(-6, 10))
	server:spectate(moderator, seen)
	rig:tick(TICKS)

	local spectators: { any } = server:spectatorsOf(viewer)
	if #spectators ~= 1 or spectators[1] ~= moderator then
		return false, `spectatorsOf named {#spectators} moderators of the viewer, not the one watching it`
	end

	local viewers: { any } = server:viewersOf(target)
	local hasViewer: boolean = table.find(viewers, viewer) ~= nil
	local hasModerator: boolean = table.find(viewers, moderator) ~= nil
	if not hasViewer or not hasModerator then
		return false, `viewersOf the target named the viewer {hasViewer} and its spectator {hasModerator}`
	end

	return true, nil
end
