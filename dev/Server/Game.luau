--[[
    The dev game's server: starts Tread's server as a consuming game does,
    builds each joining player's character on the plaza once its spawn has
    streamed in, counts their corrections, respawns it and ends it on leave
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Promise: any = require(Packages.Promise)
local Tread = require(Packages.Tread)

local Corrections = require(ServerScriptService.Server.Corrections)
local Forward = require(ServerScriptService.Server.Forward)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)
local Spawns = require(ServerScriptService.Server.Spawns)

local SETTINGS = require(ServerScriptService.Server.Config.Tread)
local STREAM_TIMEOUT: number = require(ServerScriptService.Server.Config.Spawns).streamTimeout

-- A joined player's spawn while it streams in, and then their character
type Life = {
	streaming: any, -- The Promise that builds the character once the spawn has streamed in
	character: Tread.Character?,
}

local Running: Tread.Server? = nil -- Tread's server, from the start
local Settings: Tread.ServerSettings? = nil
local Lives: { [Player]: Life } = {} -- Each joined player's, cleared when they leave

local Game = {}

--[[
    The dev game's pre-command hook. It has no items to equip and no shots
    to queue, so nothing runs before a command
--]]

local function beforeCommand(_: Tread.Character, _: Tread.Command) end

-- Builds a player's character at a spawn into their life record, counting their corrections from their first one
local function build(server: Tread.Server, player: Player, at: CFrame, life: Life): Tread.Character
	local character: Tread.Character = server:create(player, at)
	life.character = character
	Corrections.add(player)

	return character
end

--[[
    A player joined: their spawn point is held, its surroundings streamed
    in for them first, so their client never predicts its first ticks
    against parts it hasn't streamed, and then their character is built
    there. A stream the engine fails or that passes the timeout is warned
    of and the character built anyway, since reconciliation corrects a
    prediction made against a missing part
--]]

local function join(player: Player)
	if Lives[player] then
		return
	end

	local at: CFrame? = Spawns.take(player)
	if not at then
		return warn(`{player.Name} gets no character, since every spawn point on the plaza is held`)
	end

	local life: Life = { streaming = nil, character = nil }
	Lives[player] = life

	life.streaming = Promise.try(function ()
		player:RequestStreamAroundAsync(at.Position, STREAM_TIMEOUT)
	end)
		:timeout(STREAM_TIMEOUT)
		:catch(function (failure: any)
			warn(`{player.Name}'s spawn may not have streamed in before their character was built: {failure}`)
		end)
		:andThen(function ()
			-- Unless they left while it streamed
			local server: Tread.Server? = Running
			if Lives[player] == life and server then
				build(server, player, at, life)
			end
		end)
		:catch(function (failure: any)
			warn(`{player.Name} gets no character, since building it failed: {failure}`)
		end)
end

-- A player left: a spawn still streaming is cancelled, their character destroyed and their point and counts let go
local function leave(player: Player)
	local life: Life? = Lives[player]
	Lives[player] = nil
	Spawns.release(player)
	Corrections.remove(player)

	if not life then
		return
	end

	life.streaming:cancel()

	local character: Tread.Character? = life.character
	if character then
		character:destroy()
	end
end

--[[
    Starts the dev game once a server: lays the plaza's spawn points, which
    fails at once in a place without them, starts Tread's server with the
    dev shared table and the dev game's server settings, binds the
    correction telemetry, forwards each player's reports to them, and
    builds a character for each player who joins
--]]

function Game.start()
	if Running then
		error("Game.start runs once a server, and it has already run", 2)
	end

	Spawns.start()

	local settings: Tread.ServerSettings = {
		rates = SETTINGS.rates,
		catchUp = SETTINGS.catchUp,
		slots = SETTINGS.slots,
		relevancy = SETTINGS.relevancy,
		tiers = SETTINGS.tiers,
		weights = SETTINGS.weights,
		shotNear = SETTINGS.shotNear,
		budget = SETTINGS.budget,
		antiEsp = SETTINGS.antiEsp,
		footsteps = SETTINGS.footsteps,
		sleepers = SETTINGS.sleepers,
		npcs = SETTINGS.npcs,
		history = SETTINGS.history,
		rewind = SETTINGS.rewind,
		teleport = SETTINGS.teleport,
		bots = SETTINGS.bots,
		beforeCommand = beforeCommand,
	}

	local server: Tread.Server = Tread.startServer(Shared, settings)
	Running = server
	Settings = settings
	Corrections.start()
	Forward.start(server)

	-- Each lives as long as the server, and a player's teardown ends their character
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(leave)

	-- Anyone who joined before the connection gets a character too
	for _, player: Player in Players:GetPlayers() do
		join(player)
	end
end

--[[
    The running dev game: Tread's server, the shared table and the server
    settings it was started with, for a scenario or the bot harness to
    drive. It errors before the start
--]]

function Game.get(): (Tread.Server, Tread.Shared, Tread.ServerSettings)
	local server: Tread.Server? = Running
	local settings: Tread.ServerSettings? = Settings
	if not server or not settings then
		error("Game.get ran before Game.start", 2)
	end

	return server, Shared, settings
end

--[[
    Respawns a player as a game does: their character destroyed, its spawn
    point given back, a spawn taken as a join takes one and a new character
    built there into their life record, so their leave ends only the new
    one. It refuses, naming the player, one with no character, or one whose
    join's stream is still pending
--]]

function Game.respawn(player: Player): Tread.Character
	local server: Tread.Server = Game.get()
	local life: Life? = Lives[player]
	if not life then
		error(`{player.Name} has no character to respawn, since the dev game holds no life for them`, 2)
	end

	local old: Tread.Character? = life.character
	if not old then
		if life.streaming:getStatus() == Promise.Status.Started then
			error(`{player.Name}'s spawn is still streaming in, so they have no character to respawn yet`, 2)
		end

		error(`{player.Name} has no character to respawn, since building their last one failed`, 2)
	end

	-- Cleared first, so a build that throws leaves no destroyed character for their leave to destroy again
	life.character = nil
	old:destroy()
	Spawns.release(player)

	local at: CFrame? = Spawns.take(player)
	if not at then
		error(`{player.Name} gets no new character, since every spawn point on the plaza is held`, 2)
	end

	return build(server, player, at, life)
end

return Game
