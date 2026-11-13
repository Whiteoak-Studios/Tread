--[[
    The dev game's server: starts Tread's server as a consuming game does,
    with the test elevator, its call button and the fixture handlers, and
    builds, respawns and ends each player's character, counting corrections
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Promise: any = require(Packages.Promise)
local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Corrections = require(ServerScriptService.Server.Corrections)
local Elevator = require(ReplicatedStorage.Shared.Dev.Elevator)
local Forward = require(ServerScriptService.Server.Forward)
local Requests = require(ServerScriptService.Server.Fixtures.Requests)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)
local Shots = require(ServerScriptService.Server.Fixtures.Shots)
local Spawns = require(ServerScriptService.Server.Spawns)

local SETTINGS = require(ServerScriptService.Server.Config.Tread)
local STREAM_TIMEOUT: number = require(ServerScriptService.Server.Config.Spawns).streamTimeout
local PRESS_RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Press).rate

-- A joined player's spawn while it streams in, and then their character
type Life = {
	streaming: any, -- The Promise that builds the character once the spawn has streamed in
	character: Tread.Character?,
}

local Running: Tread.Server? = nil -- Tread's server, from the start
local Settings: Tread.ServerSettings? = nil
local Lives: { [Player]: Life } = {} -- Each joined player's, cleared when they leave
local LastCall: number? = nil -- os.clock() at the elevator's last call from its button, nil before any
local Sight: RaycastParams = RaycastParams.new() -- What a press's ray meets in the world, the casts' parts at start

local Game = {}

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

-- Whether a world part the dev game's casts include meets a press's ray before its end
local function blocked(origin: Vector3, direction: Vector3): boolean
	return Workspace:Raycast(origin, direction, Sight) ~= nil
end

--[[
    A press of the elevator's call button, which calls it from the next
    tick. Nothing is sent back for a press it refuses: one from a sender
    with no live character here, a bot among them, or one Elevator.accepts
    refuses on a ray along the character's cleared eye and look in the
    server's own state
--]]

local function press(player: Player | Tread.Bot, id: number)
	local server: Tread.Server? = Running
	local character: Tread.Character? = Game.characterOf(player :: Player) -- A bot holds none
	if not server or not character then
		return
	end

	-- A character that died, slept or was destroyed by other code refuses the read
	local read: boolean, state: Tread.State? = pcall(character.getState, character)
	if not read or not state then
		return
	end

	-- Whiteoak TODO: a ride timed on os.clock() ends early by any ticks the server drops under load, so a press then
	-- starts the deck again a few ticks above its rest; timing it from the call's tick closes that once the server
	-- handle gives a game its tick
	local now: number = os.clock()
	if not Elevator.accepts(id, state.eye, state.look, blocked, now, LastCall) then
		return
	end

	LastCall = now
	server:callPlatform(id)
end

--[[
    Starts the dev game once a server: lays the plaza's spawn points, which
    fails at once in a place without them, starts Tread's server with the
    dev shared table and the dev game's server settings, whose pre-command
    hook hands each command's shots to the fixture hit test, starts the
    fixture handlers, registers the test elevator and binds its call
    button, binds the correction telemetry, forwards each player's reports
    to them, and builds a character for each player who joins
--]]

function Game.start()
	if Running then
		error("Game.start runs once a server, and it has already run", 2)
	end

	Spawns.start()

	-- A press's ray meets the same parts the dev game's own casts do
	local include: { Instance }? = Shared.collision.include
	if not include then
		error("The dev game's collision names no parts for a press's ray to meet", 2)
	end

	Sight.FilterType = Enum.RaycastFilterType.Include
	Sight.FilterDescendantsInstances = include

	local settings: Tread.ServerSettings = {
		rates = SETTINGS.rates,
		catchUp = SETTINGS.catchUp,
		slots = SETTINGS.slots,
		relevancy = SETTINGS.relevancy,
		tiers = SETTINGS.tiers,
		relay = SETTINGS.relay,
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
		beforeCommand = Shots.queue,
	}

	local server: Tread.Server = Tread.startServer(Shared, settings)
	Running = server
	Settings = settings

	Shots.start(server, Shared, settings)
	Requests.start(server)

	-- The elevator and its button's listener each live as long as the server
	server:addPlatform(Elevator.platform)
	Network.rate("press", PRESS_RATE.perSecond, PRESS_RATE.burst)
	Network.press.on(press)

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
    The character the dev game holds for a player, nil while they have
    none, as while their spawn streams in or after their build failed
--]]

function Game.characterOf(player: Player): Tread.Character?
	local life: Life? = Lives[player]
	if not life then
		return nil
	end

	return life.character
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
