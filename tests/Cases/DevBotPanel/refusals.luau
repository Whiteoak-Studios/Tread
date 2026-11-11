--[[
    The bot panel refuses a spawn while a live run goes, a spawn builds or
    a run's bots are on the server, then a count past its cap alone or with
    its bots, each before it builds, and the live panel refuses a run while
    the bot panel's bots are on the server
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local LIVE: string = "dev/Server/Live.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local GOING: string = "BenchS3" -- The live run going where a case has one
local UNLISTED: string = "NoSuchRun"
local RADIUS: number = 25

type Callback = (...any) -> ()

-- One state a spawn meets, the count asked for, and the refusal it gets, nil for none
type Ask = { state: { [string]: any }, count: number, refusal: string? }

-- The panel started over stand-ins, and what the case drives and reads it by
type Panel = {
	BotPanel: any,
	listeners: { [string]: Callback }, -- Each of the dev scope's listeners the panel connected, by its event
	refused: { string }, -- Every refusal the panel sent, in order
	built: () -> number, -- The bots the fleet was asked to build
	running: { string? }, -- The live run going, which the case sets in its first place
	game: any,
}

local function idle(): { [string]: any }
	return { running = nil, building = false, made = 0, foreign = 0 }
end

-- A state with one field changed from the idle one's
local function with(field: string, value: any): { [string]: any }
	local state: { [string]: any } = idle()
	state[field] = value

	return state
end

-- The panel started over a stand-in dev game, fleet and dev scope, with no character for anyone
local function start(): Panel
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local listeners: { [string]: Callback } = {}
	local refused: { string } = {}
	local running: { string? } = { nil }
	local built: number = 0

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
			return {}
		end,

		add = function (_: any): any
			built += 1
			return {}
		end,

		clear = function (): { string }
			return {}
		end,
	}

	local fakeGame: any = {
		characterOf = function (_: any): any
			return nil
		end,
	}

	local files: { [any]: string } = { [server.BotPanel] = BOT_PANEL, [server.Bots.Run] = RUN }
	local results: { [any]: any } = {
		[server.Game] = fakeGame,
		[server.Bots.Fleet] = fleet,
		[shared.Network.Server] = network,
	}

	local BotPanel: any = Kit.loader(dataModel, files, results, loaded.require)(server.BotPanel)
	BotPanel.start(function (): string?
		return running[1]
	end)

	return {
		BotPanel = BotPanel,
		listeners = listeners,
		refused = refused,
		running = running,
		game = dataModel,

		built = function (): number
			return built
		end,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local cap: number = loaded.require(loaded.game:GetService("ServerScriptService").Server.Config.BotPanel).cap
	local panel: Panel = start()
	local BotPanel: any = panel.BotPanel

	-- 1) The order and words of every refusal, and none at the cap exactly
	local busy: { [string]: any } = { running = GOING, building = true, made = cap, foreign = 3 }
	local asks: { Ask } = {
		-- A live run going comes first, whatever else holds
		{
			state = busy,
			count = cap + 1,
			refusal = `{GOING} is running on the live panel, so the panel spawns nothing until it ends`,
		},
		{ state = with("building", true), count = 1, refusal = "a spawn is still building, so the next waits for it" },
		{
			state = with("foreign", 3),
			count = 1,
			refusal = "3 bots a run made are on the server, so the panel spawns none beside them",
		},
		{ state = idle(), count = 0, refusal = "0 is no count of bots, which is a whole number from 1" },
		{ state = idle(), count = cap + 1, refusal = `a count of {cap + 1} is past the panel's cap of {cap}` },
		{
			state = with("made", cap - 4),
			count = 5,
			refusal = `{cap - 4} panel bots and 5 more would pass the panel's cap of {cap}`,
		},
		{ state = with("made", cap - 4), count = 4, refusal = nil },
		{ state = idle(), count = cap, refusal = nil },
	}

	for index: number, ask: Ask in asks do
		local refusal: string? = BotPanel.refusal(ask.state, ask.count)
		if refusal ~= ask.refusal then
			return false, `Ask {index}, {ask.count} bots, was refused with {refusal}, not {ask.refusal}`
		end
	end

	-- 2) Through the dev scope, each refusal reaches the asker before anything is built
	local player: any = roblox.Instance.new("Player")
	player.Name = "Asker"

	panel.running[1] = GOING
	panel.listeners.botSpawn(player, 1, "Walk", nil)
	panel.running[1] = nil
	panel.listeners.botSpawn(player, cap + 1, "Idle", nil)

	-- Around me with no character, then over the whole map with no test content to find ground in
	panel.listeners.botSpawn(player, 1, "Sprint", RADIUS)
	panel.listeners.botSpawn(player, 1, "Walk", nil)
	panel.listeners.botClear(player)

	local expected: { string } = {
		`{GOING} is running on the live panel, so the panel spawns nothing until it ends`,
		`a count of {cap + 1} is past the panel's cap of {cap}`,
		"Workspace.TestContent is missing, so the panel finds no ground for the bots",
		"Workspace.TestContent is missing, so the panel finds no ground for the bots",
		"the panel has no bots on the server to clear",
	}

	-- The test content holds back the character's check, so it comes next once the content is there
	local content: any = roblox.Instance.new("Folder")
	content.Name = "TestContent"
	content.Parent = panel.game:GetService("Workspace")
	panel.listeners.botSpawn(player, 1, "Sprint", RADIUS)
	table.insert(expected, "you have no character to spawn the bots around")

	if table.concat(panel.refused, " | ") ~= table.concat(expected, " | ") then
		return false, `The panel sent the refusals: {table.concat(panel.refused, " | ")}`
	elseif panel.built() ~= 0 then
		return false, `The refused asks built {panel.built()} bots`
	elseif BotPanel.holds() then
		return false, "The panel holds bots after only refused asks"
	end

	-- 3) The live panel refuses a run while the bot panel holds bots, after its own refusals
	local liveLoaded: Harness.Loaded = Harness.load()
	local dataModel: any = liveLoaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = liveLoaded.require(shared.Dev.LiveRuns)
	local reports: { string } = {}
	local onRun: Callback? = nil

	local network: any = {
		rate = function (_: string, _: number, _: number) end,

		run = {
			on = function (callback: Callback): () -> ()
				onRun = callback

				return function () end
			end,
		},

		runReport = {
			fire = function (_: any, state: string, text: string)
				table.insert(reports, `{state}: {text}`)
			end,
		},
	}

	local holding: any = {
		holds = function (): boolean
			return true
		end,
	}

	local results: { [any]: any } = {
		[shared.Network.Server] = network,
		[server.BotPanel] = holding,
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(dataModel, { [server.Live] = LIVE }, results, liveLoaded.require)(server.Live)
	Live.start()

	local listen: Callback? = onRun
	if not listen then
		return false, "The live panel listened to no run asks"
	end

	local listed: string = LiveRuns.runs[1].name
	listen(player, UNLISTED)
	listen(player, listed)

	local wanted: string = table.concat({
		`Refused: no live run is named {UNLISTED}`,
		"Refused: the bot panel's bots are on the server, so clear the panel's bots first",
	}, " | ")

	if table.concat(reports, " | ") ~= wanted then
		return false, `The live panel answered: {table.concat(reports, " | ")}`
	elseif Live.running() ~= nil then
		return false, `A refused run left {Live.running()} running`
	end

	return true, nil
end
