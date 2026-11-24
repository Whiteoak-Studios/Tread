--[[
    The ghosts' server module, started over the dev game's mount with
    stand-ins for all it meets: the dev network, Tread's tick, relay and
    server, the shared rates, and the PreSimulation and clock a case drives
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local DevServer = require("../DevServer/Harness")

local GHOST: string = "dev/Server/Ghost.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local SLOTS: number = 4096 -- The slot table's slots, past which the relay refuses a slot as Relay.isSent does
local SIMULATION: number = 60 -- The stand-in shared table's rates, three ticks a relay tick
local RELAY: number = 20

type Callback = (...any) -> ()

-- One send of the ghosts event, as the stand-in network took it
export type Sent = { player: any, tick: number, time: number, label: string, ghosts: { any } }

-- What a case drives the started module through and reads back
export type Rig = {
	ask: (player: any, slots: { number }) -> (), -- Delivers a viewer's ask, as Volt's listener does
	leave: (player: any) -> (), -- And a viewer's leave
	frame: (now: number) -> (), -- Runs one PreSimulation with the server's clock at now
	listening: () -> number, -- The PreSimulation connections held
	character: (player: any, slot: number, root: any, velocity: any) -> (), -- A character getAll gives
	npc: (slot: number, root: any, velocity: any) -> (), -- And an NPC, each at Vector3 feet and velocity
	sent: { Sent }, -- Every send, oldest first
	sentTo: { [any]: { [number]: boolean } }, -- The slots the relay stand-in sends each viewer
	rates: { [string]: { perSecond: number, burst: number } }, -- Each endpoint's rate, as the module bound it
	config: { [string]: any }, -- The ghosts' own config, dev/Server/Config/Ghost.luau
	state: { ran: number, live: string?, label: string }, -- The ticks run, the live run going and the label
	simulation: number, -- The stand-in shared table's rates
	relay: number,
}

local Harness = {}

-- A target as getAll gives one, a character when it names a player, whose state holds the feet and velocity given
local function target(player: any, slot: number, root: any, velocity: any): any
	local state: any = { root = root, velocity = velocity }

	return {
		player = player,
		_slot = slot,
		getState = function (_: any): any
			return state
		end,
	}
end

--[[
    Loads and starts the ghosts' module in a fresh fake game: its game
    answers RunService with a PreSimulation the rig fires and Workspace
    with the rig's clock, and every module it requires but its config is a
    stand-in the rig reads and sets
--]]

function Harness.load(): Rig
	local loaded: DevServer.Loaded = DevServer.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")
	local server: any = dataModel:GetService("ServerScriptService").Server

	local listeners: { [string]: Callback } = {}
	local frames: { [{ nil }]: () -> () } = {}
	local clock: { now: number } = { now = 0 }
	local targets: { any } = {}

	local rig: Rig
	rig = {
		ask = function (player: any, slots: { number })
			listeners.ghostAsk(player, slots)
		end,

		leave = function (player: any)
			listeners.leave(player)
		end,

		frame = function (now: number)
			clock.now = now
			for _, callback: () -> () in table.clone(frames) do
				callback()
			end
		end,

		listening = function (): number
			local count: number = 0
			for _ in frames do
				count += 1
			end

			return count
		end,

		character = function (player: any, slot: number, root: any, velocity: any)
			table.insert(targets, target(player, slot, root, velocity))
		end,

		npc = function (slot: number, root: any, velocity: any)
			table.insert(targets, target(nil, slot, root, velocity))
		end,

		sent = {},
		sentTo = {},
		rates = {},
		config = loaded.require(server.Config.Ghost),
		state = { ran = 0, live = nil, label = "" },
		simulation = SIMULATION,
		relay = RELAY,
	}

	local network: any = {
		rate = function (name: string, perSecond: number, burst: number)
			rig.rates[name] = { perSecond = perSecond, burst = burst }
		end,

		ghostAsk = {
			on = function (callback: Callback): () -> ()
				listeners.ghostAsk = callback

				return function () end
			end,
		},

		ghosts = {
			fire = function (player: any, tick: number, time: number, label: string, ghosts: { any })
				table.insert(rig.sent, { player = player, tick = tick, time = time, label = label, ghosts = ghosts })
			end,
		},

		onLeave = function (callback: Callback): () -> ()
			listeners.leave = callback

			return function () end
		end,
	}

	local relay: any = {
		isSent = function (key: any, slot: number): boolean
			if slot < 0 or slot >= SLOTS or slot % 1 ~= 0 then
				error(`Relay.isSent takes one of the slot table's slots, not {slot}`, 2)
			end

			local sent: { [number]: boolean }? = rig.sentTo[key]

			return sent ~= nil and sent[slot] == true
		end,
	}

	local ticks: any = {
		counts = function (): (number, number)
			return rig.state.ran, 0
		end,
	}

	local treadServer: any = {
		getAll = function (_: any): { any }
			return table.clone(targets)
		end,
	}

	local runService: any = {
		PreSimulation = {
			Connect = function (_: any, callback: () -> ()): any
				local token: { nil } = {}
				frames[token] = callback

				return {
					Disconnect = function (_: any)
						frames[token] = nil
					end,
				}
			end,
		},
	}

	local world: any = {
		GetServerTimeNow = function (_: any): number
			return clock.now
		end,
	}

	-- The module's own game, its RunService and Workspace the stand-ins above and every other service the mount's
	local moduleGame: any = {
		GetService = function (_: any, name: string): any
			if name == "RunService" then
				return runService
			elseif name == "Workspace" then
				return world
			end

			return dataModel:GetService(name)
		end,
	}

	-- Tread and Volt are required for their types alone, so an empty table answers each
	local results: { [any]: any } = {
		[replicated.Packages.Tread] = {},
		[replicated.Packages.Volt] = {},
		[replicated.Packages.Tread.Server.Relay] = relay,
		[replicated.Packages.Tread.Server.Tick] = ticks,
		[replicated.Shared.Network.Server] = network,
		[replicated.Shared.Dev.Config] = { rates = { simulation = SIMULATION, relay = RELAY } },
	}

	local function load(instance: any): any
		local result: any = results[instance]
		if result ~= nil then
			return result
		end

		return loaded.require(instance)
	end

	local scope: { [string]: any } = { game = moduleGame, script = server.Ghost, require = load, task = task }
	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	local Ghost: any = luau.load(fs.readFile(GHOST), { debugName = GHOST, environment = scope })()
	Ghost.start(treadServer, function (): string
		return rig.state.label
	end, function (): string?
		return rig.state.live
	end)

	return rig
end

return Harness
