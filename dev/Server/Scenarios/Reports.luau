--[[
    Counts every report Tread raises over a window by kind, for each real
    player, for the bots together and for no player, prints a line for
    each, and passes
--]]

--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Game = require(ServerScriptService.Server.Game)

local WINDOW: number = require(ServerScriptService.Server.Config.Reports).window

type Counts = { [string]: number }

-- One more report of a kind in a tally
local function add(counts: Counts, kind: string)
	counts[kind] = (counts[kind] or 0) + 1
end

return function (): (boolean, string | nil)
	local server: Tread.Server = Game.get()
	local byPlayer: { [Player]: Counts } = {}
	local bots: Counts = {}
	local nobody: Counts = {} -- An NPC's and the server's own

	-- Disconnected once the window ends
	local stop: () -> () = server:onReport(function (player: (Player | Tread.Bot)?, kind: string, _: number | string)
		if player == nil then
			add(nobody, kind)
		elseif typeof(player) == "Instance" then
			local real: Player = player :: Player -- A bot is a table, so an Instance here is a Player
			local counts: Counts = byPlayer[real] or {}
			byPlayer[real] = counts
			add(counts, kind)
		else
			add(bots, kind)
		end
	end)

	task.wait(WINDOW)
	stop()

	-- Every real player in at the end, those who raised none included, beside any who raised some and left
	for _, player: Player in Players:GetPlayers() do
		byPlayer[player] = byPlayer[player] or {}
	end

	local players: { Player } = {}
	for player: Player in byPlayer do
		table.insert(players, player)
	end

	table.sort(players, function (a: Player, b: Player): boolean
		return a.Name < b.Name
	end)

	for _, player: Player in players do
		print(`Reports {player.Name}: {HttpService:JSONEncode(byPlayer[player])}`)
	end

	print(`Reports bots: {HttpService:JSONEncode(bots)}`)
	print(`Reports no player: {HttpService:JSONEncode(nobody)}`)

	return true, nil
end
