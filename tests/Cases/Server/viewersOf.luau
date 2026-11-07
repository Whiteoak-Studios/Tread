--[[
    server:viewersOf names the Players currently sent a target, a bot never
    among them, and none for a target destroyed; server:keyframe holds what
    a viewer is sent; reportShotNear takes a shooter with no character
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3
local PING: number = 0.05 -- Seconds the Lune player's engine ping reports

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)

	local player: any = roblox.Instance.new("Player")
	Pings[player] = PING
	local bot: any = rig.mock:addBot("Bot")

	local watcher: any = server:create(player, rig:at(0, 0))
	local watched: any = server:create(bot, rig:at(6, 0))
	rig:tick(TICKS)

	local viewers: { any } = server:viewersOf(watched)
	if #viewers ~= 1 or viewers[1] ~= player then
		return false, `viewersOf the bot's character named {#viewers} viewers, not the player beside it`
	end

	-- The bot is sent the player's character too, but a bot is no Player
	if #server:viewersOf(watcher) ~= 0 then
		return false, "viewersOf named a bot among a target's viewers"
	end

	local keyframe: any = Keyframe.read(server:keyframe(player))
	if #keyframe.characters ~= 1 or keyframe.characters[1].kind ~= "Player" then
		return false, `The player's keyframe holds {#keyframe.characters} characters, not the bot's`
	end

	server:reportShotNear(bot, player)
	server:reportShotNear(rig.mock:addBot("Nobody"), player)

	watched:destroy()
	if #server:viewersOf(watched) ~= 0 then
		return false, "viewersOf a destroyed target named viewers"
	elseif pcall(server.viewersOf, server, "Bot") then
		return false, "viewersOf took a string for its target"
	end

	return true, nil
end
