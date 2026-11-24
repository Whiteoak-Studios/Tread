--[[
    The ghosts' client module, loaded over the dev game's mount with
    stand-ins for all it meets: the dev network, Tread's client handle and
    interpolation, the frames, keys and touch button, and the server's clock
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod
local task = require("@lune/task")

local DevServer = require("../DevServer/Harness")
local Pings = require("../Connections/Ping")

local GHOST: string = "dev/Client/Ghost.luau"
local CONFIG: string = "dev/Client/Config.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local RELAY: number = 20 -- The stand-in shared table's relay rate, the dev table's
local RADIUS: number = 1.39 -- Its hull, the dev table's
local STANDING: number = 5
local CROUCHED: number = 3.06
local PING: number = 0.06 -- Seconds of network ping the local player reports unless a case sets another
local DELAY: number = 0.15 -- Seconds of interpolation delay unless a case sets another

type Callback = (...any) -> ()

-- What the device says of itself, as UserInputService gives it
export type Device = {
	touch: boolean,
	keyboard: boolean,
}

-- What each stand-in listener list holds, counted for a case
export type Listening = {
	frames: number, -- PreRender connections
	keys: number, -- InputBegan connections
	spawned: number, -- The handle's spawn listeners
	despawned: number,
	ghosts: number, -- The dev scope's ghosts listener, at most one
}

-- What a case drives the module through and reads back
export type Rig = {
	Ghost: any, -- The module as loaded
	config: { [string]: any }, -- The ghost block of the dev client's config
	shared: { [string]: any }, -- The stand-in shared table the module takes its hull and relay rate from
	player: any, -- The local player, whose ping Pings holds
	playerGui: any,
	workspace: any, -- The module's Workspace, whose camera a case moves
	asks: { { number } }, -- A copy of every ask fired, oldest first
	buttons: { any }, -- Each touch button the module made, a stand-in whose Activated a case taps
	set: { renderTime: number, delay: number }, -- What the handle's render time and the interpolation's delay give
	start: () -> (), -- Ghost.start with the stand-in handle
	press: (key: any, processed: boolean?) -> (), -- A key going down, which the game may have taken
	tap: (button: any) -> (),
	clock: (now: number) -> (), -- Sets the server's clock as the client reads it
	frame: (now: number) -> (), -- Sets it, then runs one PreRender
	send: (tick: number, time: number, label: string, ghosts: { { [string]: number } }) -> (), -- The ghosts event
	spawn: (id: number, player: any?, kind: string?) -> (), -- A rig the handle draws, its spawn told to each listener
	despawn: (id: number) -> (),
	pose: (id: number, feet: vector?, posture: string?, platform: number?) -> (), -- What Interpolate.pose draws
	listening: () -> Listening,
}

-- A drawn pose a case sets, which the interpolation's stand-in copies into the state it is handed
type Pose = { feet: vector, posture: string, platform: number }

-- Each fake Workspace's server clock: Lune's Workspace has no GetServerTimeNow, so each answers its own, registered
-- once for the whole run, since Lune refuses a method registered twice
local Clocks: { [any]: number } = {}

roblox.implementMethod("Workspace", "GetServerTimeNow", function (workspace: any): number
	return Clocks[workspace]
end)

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A list's listener taken out, as its disconnect does
local function remove(list: { Callback }, callback: Callback)
	local index: number? = table.find(list, callback)
	if index then
		table.remove(list, index)
	end
end

-- A signal over a list a case fires and counts, as an engine signal's Connect hands back a connection
local function signal(list: { Callback }): any
	return {
		Connect = function (_: any, callback: Callback): any
			table.insert(list, callback)

			return {
				Disconnect = function (_: any)
					remove(list, callback)
				end,
			}
		end,
	}
end

local function fire(list: { Callback }, ...: any)
	for _, callback: Callback in table.clone(list) do
		callback(...)
	end
end

local Client = {}

--[[
    Loads the ghosts' module in a fresh fake game on a device, a desktop's
    unless given. Its game answers RunService, UserInputService, Workspace
    and Players with stand-ins the rig drives, its Instance.new makes a
    stand-in for a TextButton, whose taps Lune's GUI objects lack, and every
    module it requires but its config and Tread's own step modules is a
    stand-in the rig reads and sets. Nothing starts until the case starts it
--]]

function Client.load(device: Device?): Rig
	local given: Device = device or { touch = false, keyboard = true }
	local loaded: DevServer.Loaded = DevServer.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")
	local tread: any = replicated.Packages.Tread

	local frames: { Callback } = {}
	local keys: { Callback } = {}
	local spawned: { Callback } = {}
	local despawned: { Callback } = {}
	local ghosts: { Callback } = {}
	local queued: { { any } } = {} -- Messages the ghosts event took while nothing listened, as Volt queues them
	local rigged: { [number]: any } = {} -- The stand-in handle's _rigged
	local poses: { [number]: Pose } = {}

	local player: any = roblox.Instance.new("Player")
	player.Name = "Viewer"
	local playerGui: any = create("PlayerGui", "PlayerGui", player)
	Pings[player] = PING

	local workspace: any = roblox.Instance.new("Workspace")
	Clocks[workspace] = 0

	local shared: { [string]: any } = {
		rates = { simulation = RELAY, relay = RELAY },
		step = { radius = RADIUS, standing = STANDING, crouched = CROUCHED },
	}

	local rig: Rig
	local handle: any = {
		_rigged = rigged,

		onSpawned = function (_: any, callback: Callback): () -> ()
			table.insert(spawned, callback)

			return function ()
				remove(spawned, callback)
			end
		end,

		onDespawned = function (_: any, callback: Callback): () -> ()
			table.insert(despawned, callback)

			return function ()
				remove(despawned, callback)
			end
		end,

		getRenderTime = function (_: any): number
			return rig.set.renderTime
		end,
	}

	-- Interpolate.pose fills the state with the pose a case set, on the ground, and the delay is the rig's
	local interpolate: any = {
		pose = function (slot: number, into: any): (boolean, number, number, number)
			local pose: Pose? = poses[slot]
			if not pose then
				return false, 0, 0, 0
			end

			into.position = pose.feet
			into.posture = pose.posture
			into.mode = "Ground"
			into.platform = pose.platform
			into.facing = 0

			return true, 0, 0, 0
		end,

		delay = function (): number
			return rig.set.delay
		end,
	}

	-- The dev scope's client module, with the ask the module fires and the ghosts event it listens to, which holds one
	-- listener and hands it what queued before it, as Volt's single mode does
	local network: any = {
		ghostAsk = {
			fire = function (slots: { number })
				table.insert(rig.asks, table.clone(slots))
			end,
		},

		ghosts = {
			on = function (callback: Callback): () -> ()
				if #ghosts > 0 then
					error("ghosts: a listener is already connected")
				end

				table.insert(ghosts, callback)
				local waiting: { { any } } = table.clone(queued)
				table.clear(queued)

				for _, message: { any } in waiting do
					callback(message[1], message[2], message[3], message[4])
				end

				return function ()
					remove(ghosts, callback)
				end
			end,
		},
	}

	local services: { [string]: any } = {
		RunService = { PreRender = signal(frames) },
		UserInputService = { TouchEnabled = given.touch, KeyboardEnabled = given.keyboard, InputBegan = signal(keys) },
		Workspace = workspace,
		Players = { LocalPlayer = player },
	}

	local moduleGame: any = {
		GetService = function (_: any, name: string): any
			return services[name] or dataModel:GetService(name)
		end,
	}

	-- A TextButton whose Activated a case fires, since Lune's GUI objects have no signals; every other class is real
	local instance: any = {
		new = function (className: string): any
			if className ~= "TextButton" then
				return roblox.Instance.new(className)
			end

			local taps: { Callback } = {}
			local button: { [string]: any } = { ClassName = className, Activated = signal(taps), taps = taps }
			table.insert(rig.buttons, button)

			return button
		end,
	}

	local folder: any = create("Folder", "Client", replicated)
	local ghostModule: any = create("ModuleScript", "Ghost", folder)
	local configModule: any = create("ModuleScript", "Config", folder)
	local files: { [any]: string } = { [ghostModule] = GHOST, [configModule] = CONFIG }

	-- Tread is required for its types alone, so an empty table answers it
	local results: { [any]: any } = {
		[tread] = {},
		[tread.Client.Interpolate] = interpolate,
		[replicated.Shared.Network.Client] = network,
		[replicated.Shared.Dev.Config] = shared,
	}

	local function load(target: any): any
		local result: any = results[target]
		if result ~= nil then
			return result
		end

		local path: string? = files[target]
		if not path then
			return loaded.require(target)
		end

		local scope: { [string]: any } = { game = moduleGame, script = target, require = load, task = task }
		for name: string, value: any in roblox do
			if name:match(DATATYPE) then
				scope[name] = value
			end
		end

		scope.Instance = instance

		local chunk: () -> any = luau.load(fs.readFile(path), { debugName = path, environment = scope })
		results[target] = chunk()

		return results[target]
	end

	local Ghost: any = load(ghostModule)

	rig = {
		Ghost = Ghost,
		config = load(configModule).ghost,
		shared = shared,
		player = player,
		playerGui = playerGui,
		workspace = workspace,
		asks = {},
		buttons = {},
		set = { renderTime = 0, delay = DELAY },

		start = function ()
			Ghost.start(handle)
		end,

		press = function (key: any, processed: boolean?)
			fire(keys, { KeyCode = key, UserInputType = roblox.Enum.UserInputType.Keyboard }, processed == true)
		end,

		tap = function (button: any)
			fire(button.taps)
		end,

		clock = function (now: number)
			Clocks[workspace] = now
		end,

		frame = function (now: number)
			Clocks[workspace] = now
			fire(frames, 0)
		end,

		send = function (tick: number, time: number, label: string, sent: { { [string]: number } })
			if #ghosts == 0 then
				table.insert(queued, { tick, time, label, sent })
				return
			end

			fire(ghosts, tick, time, label, sent)
		end,

		spawn = function (id: number, owner: any?, kind: string?)
			local slot: { [string]: any } = { id = id, kind = kind or "Player", player = owner, withheld = false }
			rigged[id] = slot
			fire(spawned, slot, nil)
		end,

		despawn = function (id: number)
			local slot: any = rigged[id]
			rigged[id] = nil
			fire(despawned, slot)
		end,

		pose = function (id: number, feet: vector?, posture: string?, platform: number?)
			if not feet then
				poses[id] = nil
				return
			end

			poses[id] = { feet = feet, posture = posture or "Stand", platform = platform or 0 }
		end,

		listening = function (): Listening
			return {
				frames = #frames,
				keys = #keys,
				spawned = #spawned,
				despawned = #despawned,
				ghosts = #ghosts,
			}
		end,
	}

	return rig
end

return Client
