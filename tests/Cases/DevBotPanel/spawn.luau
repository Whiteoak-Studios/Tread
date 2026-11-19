--[[
    A spawn builds its bots on the ground around the asker or over the
    whole map, leaves out those over nothing or that fail, counts toward the
    cap, and Clear removes them, while a watcher leaving clears nothing
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod
local task = require("@lune/task")

local Harness = require("../../Fixtures/DevServer/Harness")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local GROUND: number = 12 -- The height the stand-in ground answers every cast at
local ROOT: any = roblox.Vector3.new(300, 20, -150) -- The asker's character, inside the play bound
local RADIUS: number = 25
local NEAR: number = 3 -- Bots built around the asker
local FAR: number = 2 -- Bots built over the whole map
local FAILING: string = "a stand-in build failure" -- What the fleet throws for the bot the case fails

type Callback = (...any) -> ()

-- What a cast meets, the stand-in ground everywhere until the case takes it away
local Ground: { over: boolean } = { over = true }

-- Lune's Workspace has no Raycast, so this case's answers with flat ground at GROUND, or nothing once taken away
roblox.implementMethod("Workspace", "Raycast", function (_: any, origin: any, _: any, _: any): any
	if not Ground.over then
		return nil
	end

	return { Position = roblox.Vector3.new(origin.X, GROUND, origin.Z) }
end)

-- Lune has no RaycastParams, so the panel's casts are handed a plain table to set their filter on
local Params: { [string]: any } = {
	new = function (): { [string]: any }
		return {}
	end,
}

--[[
    A require for the case's dev modules, each run once with script set to
    it, the Roblox datatypes and the stand-in RaycastParams in scope, each
    answer already in results handed back and anything else to the fallback
--]]

local function loader(
	dataModel: any,
	files: { [any]: string },
	results: { [any]: any },
	fallback: (target: any) -> any
): (target: any) -> any
	local function load(target: any): any
		local result: any = results[target]
		if result ~= nil then
			return result
		end

		local path: string? = files[target]
		if not path then
			return fallback(target)
		end

		local scope: { [string]: any } = { game = dataModel, script = target, require = load, task = task }
		for name: string, value: any in roblox do
			if name:match(DATATYPE) then
				scope[name] = value
			end
		end

		scope.RaycastParams = Params

		local chunk: () -> any = luau.load(fs.readFile(path), { debugName = path, environment = scope })
		results[target] = chunk()

		return results[target]
	end

	return load
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local cap: number = loaded.require(server.Config.BotPanel).cap
	local tries: number = loaded.require(server.Config.BotPanel).tries
	local lift: number = loaded.require(server.Bots.Config).spawn.lift
	local map: any = loaded.require(server.Bots.Config).scenarios.S2.groups[1].spawn

	local listeners: { [string]: Callback } = {}
	local refused: { string } = {}
	local entries: { any } = {}
	local cleared: number = 0
	local fail: boolean = false
	local opened: number = 0 -- Windows the panel opened, each the first watcher's connect of its listener

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
				table.insert(refused, reason)
			end,
		},

		botStats = { fire = function () end },
	}

	local fleet: any = {
		entries = function (): { any }
			return entries
		end,

		add = function (plan: any): any
			if fail then
				fail = false
				error(FAILING, 0)
			end

			table.insert(entries, plan)
			return plan
		end,

		clear = function (): { string }
			cleared += 1
			table.clear(entries)

			return {}
		end,
	}

	local character: any = {
		getState = function (_: any): any
			return { root = ROOT }
		end,
	}

	local fakeGame: any = {
		get = function (): (any, any, any)
			return {}, { step = { walk = 16, sprint = 24 }, rates = { simulation = 20 } }, {}
		end,

		characterOf = function (_: any): any
			return character
		end,
	}

	-- The tick's counts, read as each window opens
	local tick: any = {
		counts = function (): (number, number)
			opened += 1
			return 0, 0
		end,

		stages = function (): { any }
			return {}
		end,
	}

	local content: any = roblox.Instance.new("Folder")
	content.Name = "TestContent"
	content.Parent = dataModel:GetService("Workspace")

	local files: { [any]: string } = { [server.BotPanel] = BOT_PANEL, [server.Bots.Run] = RUN }
	local results: { [any]: any } = {
		[server.Game] = fakeGame,
		[server.Bots.Fleet] = fleet,
		[shared.Network.Server] = network,
		[dataModel:GetService("ReplicatedStorage").Packages.Tread.Server.Tick] = tick,
	}

	local BotPanel: any = loader(dataModel, files, results, loaded.require)(server.BotPanel)
	BotPanel.start(function (): string?
		return nil
	end)

	local asker: any = roblox.Instance.new("Player")
	asker.Name = "Asker"

	-- 1) Around the asker: each bot on the ground inside the square, facing its own way, with a program of its own
	listeners.botSpawn(asker, NEAR, "Walk", RADIUS)
	if #entries ~= NEAR or #refused ~= 0 then
		return false, `A spawn of {NEAR} built {#entries} with the refusals {table.concat(refused, " | ")}`
	end

	local names: { [string]: boolean } = {}
	for _, plan: any in entries do
		local at: any = plan.at.Position
		if math.abs(at.X - ROOT.X) > RADIUS or math.abs(at.Z - ROOT.Z) > RADIUS then
			return false, `{plan.name} was built at {at}, outside {RADIUS} studs either way of {ROOT}`
		elseif math.abs(at.Y - (GROUND + lift)) > 1e-6 then
			return false, `{plan.name} stands at {at.Y}, not {lift} studs over the ground at {GROUND}`
		elseif plan.group ~= "panel" or type(plan.steer) ~= "function" or names[plan.name] then
			return false, `{plan.name} was built in {plan.group}, its program a {type(plan.steer)}, or twice`
		end

		names[plan.name] = true
	end

	if not BotPanel.holds() then
		return false, "The panel holds no bots after building some"
	end

	-- 2) Over the whole map, idle, inside the harness's map
	listeners.botSpawn(asker, FAR, "Idle", nil)
	for index: number = NEAR + 1, #entries do
		local at: any = entries[index].at.Position
		local offset: any = at - map.center
		if math.abs(offset.X) > map.size.X / 2 or math.abs(offset.Z) > map.size.Y / 2 then
			return false, `A whole-map bot was built at {at}, outside the map`
		end
	end

	-- 3) The panel's bots count toward the cap
	local made: number = NEAR + FAR
	listeners.botSpawn(asker, cap - made + 1, "Walk", nil)
	local past: string = `{made} panel bots and {cap - made + 1} more would pass the panel's cap of {cap}`
	if refused[#refused] ~= past or #entries ~= made then
		return false, `A spawn past the cap with {made} panel bots out got {refused[#refused]}`
	end

	-- 4) Over nothing, every try misses and the bot is left out, and a build that fails is left out too
	Ground.over = false
	listeners.botSpawn(asker, 1, "Walk", nil)
	Ground.over = true
	fail = true
	listeners.botSpawn(asker, 2, "Sprint", nil)

	local missed: string = `0 of the 1 bots were built: 1 found no ground in {tries} tries`
	local failed: string = `1 of the 2 bots were built: 1 failed to build, the first with: {FAILING}`
	if refused[#refused - 1] ~= missed or refused[#refused] ~= failed then
		return false, `The left-out bots were told as: {refused[#refused - 1]} | {refused[#refused]}`
	elseif #entries ~= made + 1 then
		return false, `{#entries} bots stood after the left-out spawns, not {made + 1}`
	end

	-- 5) Watchers come and go, the first opening a window and a leave clearing nothing but its own watch
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	listeners.botWatch(asker, true)
	listeners.botWatch(other, true)
	listeners.leave(asker)
	listeners.botWatch(asker, true) -- Back while the other still watches, so the window stays open
	listeners.botWatch(other, false)
	listeners.leave(asker)
	listeners.botWatch(other, true) -- Every watcher gone, so a new window opens
	listeners.botWatch(other, false)

	if opened ~= 2 then
		return false, `The watchers opened {opened} windows, not the 2 their comings and goings make`
	elseif cleared ~= 0 or #entries ~= made + 1 then
		return false, "A watcher leaving took bots with them"
	end

	-- 6) Clear removes every bot the panel made, and a second finds none
	listeners.botClear(asker)
	listeners.botClear(asker)
	if cleared ~= 1 or BotPanel.holds() then
		return false, `Clear cleared the fleet {cleared} times, the panel holding bots after: {BotPanel.holds()}`
	elseif refused[#refused] ~= "the panel has no bots on the server to clear" then
		return false, `A second Clear was answered with {refused[#refused]}`
	end

	return true, nil
end
