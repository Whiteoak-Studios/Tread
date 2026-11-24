--[[
    On a server started with relay workers, the bot panel's spawn has the
    relay make its bots' views on the workers, a run inside the build and
    the first after it, and a view made later in process. With no workers
    started, the spawn leaves the relay's mode alone
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local Harness = require("../../Fixtures/DevServer/Harness")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local GROUND: number = 12 -- The height the stand-in ground answers every cast at
local FRAME: number = 1 / 60 -- Seconds a stand-in Heartbeat gives
local WORKERS: number = 4
local PLAYER: string = "Mike" -- The real player, whose view was made before the spawn
local LATER: string = "Joiner" -- A real player whose view is made after it

type Callback = (...any) -> ()

-- The stand-in server's relay as the case drives it: each relay run makes a view for every viewer that has none yet, on
-- the workers while they are on and in process otherwise, as Relay.run's made does
type World = {
	ran: number, -- Ticks the stand-in loop has run, each one a relay tick
	relayTick: number, -- The tick the relay stage's newest run was handed, 0 before any
	workersOn: boolean, -- What Relay.useWorkers last set
	switched: { string }, -- Each Relay.useWorkers call, as text
	viewers: { string }, -- Every viewer by name, in the order its character was made
	homes: { [string]: string }, -- Each viewer's home, "workers" or "process", once a run made its view
	waits: number, -- The Heartbeats the panel waited
	refused: { string },
}

local function relayRun(world: World)
	world.ran += 1
	world.relayTick = world.ran

	for _, name: string in world.viewers do
		if world.homes[name] == nil then
			world.homes[name] = world.workersOn and "workers" or "process"
		end
	end
end

--[[
    The panel started on a server with that many relay workers, over a
    stand-in dev game, fleet, dev scope, relay and tick loop, its Workspace
    flat ground and each Heartbeat it waits one relay run, with the real
    player's view made in a run before. Gives the world and the spawn ask
--]]

local function start(workers: number): (World, Callback)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	local world: World = {
		ran = 0,
		relayTick = 0,
		workersOn = false,
		switched = {},
		viewers = { PLAYER },
		homes = {},
		waits = 0,
		refused = {},
	}

	relayRun(world)

	local listeners: { [string]: Callback } = {}
	local function listen(name: string): any
		return {
			on = function (callback: Callback): () -> ()
				listeners[name] = callback

				return function () end
			end,
		}
	end

	local network: any = {
		rate = function (_: string, _: number, _: number) end,
		botSpawn = listen("botSpawn"),
		botClear = listen("botClear"),
		botWatch = listen("botWatch"),

		onLeave = function (callback: Callback): () -> ()
			listeners.leave = callback

			return function () end
		end,

		botRefused = {
			fire = function (_: any, reason: string)
				table.insert(world.refused, reason)
			end,
		},

		botStats = { fire = function () end },
	}

	local entries: { any } = {}
	local fleet: any = {
		entries = function (): { any }
			return entries
		end,

		add = function (plan: any): any
			table.insert(entries, plan)
			table.insert(world.viewers, plan.name)

			return plan
		end,
	}

	local fakeGame: any = {
		get = function (): (any, any, any)
			return {}, { step = { walk = 16, sprint = 24 }, rates = { simulation = 20 } }, {}
		end,

		characterOf = function (_: any): any
			return nil
		end,
	}

	local relay: any = {
		useWorkers = function (on: boolean)
			world.workersOn = on
			table.insert(world.switched, tostring(on))
		end,
	}

	-- The relay stage as the tick loop keeps it, a ring of one holding its newest run's tick
	local tick: any = {
		counts = function (): (number, number)
			return world.ran, 0
		end,

		stages = function (): { any }
			local held: number = world.relayTick > 0 and 1 or 0
			return {
				{ name = "relay", times = { 0 }, ticks = { world.relayTick }, beats = { 0 }, held = held, head = 0 },
			}
		end,
	}

	local run: any = {
		workers = function (): number
			return workers
		end,
	}

	local runService: any = {
		Heartbeat = {
			Wait = function (_: any): number
				world.waits += 1
				relayRun(world)

				return FRAME
			end,
		},
	}

	local content: any = roblox.Instance.new("Folder")
	content.Name = "TestContent"

	local workspace: any = {
		FindFirstChild = function (_: any, name: string): any
			if name == content.Name then
				return content
			end

			return nil
		end,

		Raycast = function (_: any, origin: any, _: any, _: any): any
			return { Position = roblox.Vector3.new(origin.X, GROUND, origin.Z) }
		end,
	}

	local panelGame: any = {
		GetService = function (_: any, name: string): any
			if name == "RunService" then
				return runService
			elseif name == "Workspace" then
				return workspace
			end

			return dataModel:GetService(name)
		end,
	}

	local results: { [any]: any } = {
		[server.Game] = fakeGame,
		[server.Bots.Fleet] = fleet,
		[server.Bots.Run] = run,
		[replicated.Shared.Network.Server] = network,
		[replicated.Packages.Tread.Server.Relay] = relay,
		[replicated.Packages.Tread.Server.Tick] = tick,
	}

	-- The panel runs with the stand-in game and Lune's datatypes in scope, and RaycastParams, which Lune lacks, as a
	-- plain table to set the casts' filter on
	local scope: { [string]: any } = { game = panelGame, script = server.BotPanel, task = task }
	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	scope.RaycastParams = {
		new = function (): { [string]: any }
			return {}
		end,
	}

	scope.require = function (target: any): any
		local result: any = results[target]
		if result ~= nil then
			return result
		end

		return loaded.require(target)
	end

	local BotPanel: any = luau.load(fs.readFile(BOT_PANEL), { debugName = BOT_PANEL, environment = scope })()
	BotPanel.start(function (): string?
		return nil
	end)

	return world, listeners.botSpawn
end

-- The homes of every viewer but the real player, in the order made, each name's
local function botHomes(world: World): { string }
	local homes: { string } = {}
	for _, name: string in world.viewers do
		if name ~= PLAYER then
			table.insert(homes, world.homes[name] or "none")
		end
	end

	return homes
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local batch: number = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Config).spawn.batch
	local count: number = batch + 2 -- A batch, a frame between, then two more, so one run falls inside the build

	local asker: any = roblox.Instance.new("Player")
	asker.Name = PLAYER

	-- 1) With workers: on before the first bot, off once the first run after the build has made the last two
	local world: World, spawn: Callback = start(WORKERS)
	spawn(asker, count, "Idle", nil)

	local homes: { string } = botHomes(world)
	if #homes ~= count or #world.refused ~= 0 then
		return false, `A spawn of {count} made {#homes} views, refused with: {table.concat(world.refused, " | ")}`
	end

	for index: number, home: string in homes do
		if home ~= "workers" then
			return false, `Panel bot {index}'s view was made {home}, not on the workers`
		end
	end

	if table.concat(world.switched, ",") ~= "true,false" or world.waits ~= 2 then
		local switched: string = table.concat(world.switched, ",")
		return false, `The spawn switched the workers {switched} over {world.waits} Heartbeats, not true,false over 2`
	elseif world.homes[PLAYER] ~= "process" then
		return false, `The real player's view, made before the spawn, is {world.homes[PLAYER]}`
	end

	-- A real player whose character is made after the spawn gets their view at the next run, in process
	table.insert(world.viewers, LATER)
	relayRun(world)
	if world.homes[LATER] ~= "process" then
		return false, `A view made after the spawn went to {world.homes[LATER]}, not in process`
	end

	-- 2) With no workers started, the spawn leaves the relay's mode alone, waits only between its batches, and every
	-- view is made in process, the last two at the run after the build
	local serial: World, serialSpawn: Callback = start(0)
	serialSpawn(asker, count, "Idle", nil)
	relayRun(serial)

	for index: number, home: string in botHomes(serial) do
		if home ~= "process" then
			return false, `With no workers, panel bot {index}'s view was made {home}`
		end
	end

	if #serial.switched ~= 0 or serial.waits ~= 1 then
		return false,
			`With no workers the spawn switched the workers {#serial.switched} times over {serial.waits} waits`
	end

	return true, nil
end
