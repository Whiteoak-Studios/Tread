--[[
    GoA0 sends to the A0 arm's place, refuses in Studio and with no real
    player in, tries a teleport that throws or fails again on one reserved
    server until it starts, and fails once its tries run out
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementProperty
local serde = require("@lune/serde")
local task = require("@lune/task")

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SCENARIO: string = "dev/Server/Scenarios/GoA0.luau"
local PROJECT: string = "arm-a0.project.json" -- The A0 place's project, whose servePlaceIds names the place
local THROWN: string = "the case's refusal"
local FAILED: string = "the case's failure"

-- The case's own tries and waits, so its answers stand whatever the dev server tunes
local VALUES: { [string]: number } = {
	attempts = 3,
	retryDelay = 0,
	floodDelay = 0,
	callWait = 1,
	settle = 1,
}

local STUDIO: string =
	"it sends players to a live server of the A0 place, so it runs on a live server of the dev place only"
local EMPTY: string = "no real player is in to send to the A0 place"
local RETRIED: string = "a teleport started for Mike to reserved server guid false of place 108848112043191 on try 3; "
	.. `try 1: TeleportAsync threw: {THROWN}; try 2: Mike's teleport failed with Failure: {FAILED}`
local RAN_OUT: string = "no teleport started for Mike in 3 tries; "
	.. `try 1: TeleportAsync threw: {THROWN}; try 2: TeleportAsync threw: {THROWN}; try 3: TeleportAsync threw: {THROWN}`
local CALL: string = "108848112043191 Mike guid false" -- Each call: the place, the players and the reserved server's id

-- What one run of the scenario did
type Outcome = {
	passed: boolean,
	reason: string?,
	calls: { string },
	listening: boolean, -- Whether TeleportInitFailed still had its listener after the run
}

-- Lune's TeleportOptions predates ReservedServerId, so each options instance keeps the one the scenario sets
local Ids: { [any]: string } = {}
roblox.implementProperty("TeleportOptions", "ReservedServerId", function (options: any): string
	return Ids[options] or ""
end, function (options: any, id: string)
	Ids[options] = id
end)

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

--[[
    Runs the scenario once over stand-ins for TeleportService, RunService,
    HttpService and Players. Each TeleportAsync call takes its step: throw,
    fail through TeleportInitFailed, or anything else, every player leaving
--]]

local function run(loaded: Harness.Loaded, steps: { string }, studio: boolean, real: { any }): Outcome
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local calls: { string } = {}
	local listener: any = nil

	local teleport: any = {
		TeleportInitFailed = {
			Connect = function (_: any, callback: any): any
				listener = callback

				return {
					Disconnect = function ()
						listener = nil
					end,
				}
			end,
		},

		TeleportAsync = function (_: any, placeId: number, players: { any }, options: any): any
			local step: string? = steps[#calls + 1]
			local named: { string } = {}
			for _, player: any in players do
				table.insert(named, player.Name)
			end

			table.insert(calls, `{placeId} {table.concat(named, ",")} {options.ReservedServerId}`)
			if step == "throw" then
				error(THROWN, 0)
			end

			-- After the call answers, as the engine's TeleportInitFailed and a player's leaving come
			task.defer(function ()
				for _, player: any in players do
					if step == "fail" then
						listener(player, roblox.Enum.TeleportResult.Failure, FAILED, placeId, options)
					else
						player.Parent = nil
					end
				end
			end)

			return {}
		end,
	}

	local services: { [string]: any } = {
		TeleportService = teleport,
		HttpService = {
			GenerateGUID = function (_: any, wrapped: boolean): string
				return `guid {wrapped}`
			end,
		},
		Players = {
			GetPlayers = function (_: any): { any }
				return real
			end,
		},
		RunService = {
			IsStudio = function (_: any): boolean
				return studio
			end,
			Heartbeat = dataModel:GetService("RunService").Heartbeat,
		},
	}

	local place: any = {
		GetService = function (_: any, name: string): any
			return services[name] or dataModel:GetService(name)
		end,
	}

	local values: { [string]: number } = table.clone(VALUES)
	values.placeId = loaded.require(server.Config.GoA0).placeId

	local files: { [any]: string } = { [server.Scenarios.GoA0] = SCENARIO }
	local results: { [any]: any } = { [server.Config.GoA0] = values }
	local scenario: any = Kit.loader(place, files, results, loaded.require)(server.Scenarios.GoA0)
	local passed: boolean, reason: string? = scenario()

	return { passed = passed, reason = reason, calls = calls, listening = listener ~= nil }
end

-- The outcome against what it should be, nil when they match
local function check(name: string, outcome: Outcome, passed: boolean, reason: string, calls: number): string?
	local wanted: string = table.concat(table.create(calls, CALL), " | ")
	local made: string = table.concat(outcome.calls, " | ")
	if outcome.passed ~= passed or outcome.reason ~= reason then
		return `{name} gave {outcome.passed} with "{outcome.reason}", not {passed} with "{reason}"`
	elseif made ~= wanted then
		return `{name} made the calls "{made}", not "{wanted}"`
	elseif outcome.listening then
		return `{name} left its TeleportInitFailed listener connected`
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local players: any = loaded.game:GetService("Players")

	-- 1) The run sends to the place the A0 project serves
	local project: any = serde.decode("json", fs.readFile(PROJECT))
	local placeId: number = loaded.require(loaded.game:GetService("ServerScriptService").Server.Config.GoA0).placeId
	if placeId ~= project.servePlaceIds[1] then
		return false, `GoA0 sends to place {placeId}, while {PROJECT} serves {project.servePlaceIds[1]}`
	end

	-- 2) Studio refuses before any call, and so does a server with no real player in
	local studio: string? =
		check("Studio", run(loaded, {}, true, { create("Player", "Mike", players) }), false, STUDIO, 0)
	local empty: string? = check("No real player", run(loaded, {}, false, {}), false, EMPTY, 0)
	if studio or empty then
		return false, studio or empty
	end

	-- 3) A call that throws, then one TeleportInitFailed fails, are tried again on the one reserved server until it starts
	local retried: Outcome = run(loaded, { "throw", "fail", "leave" }, false, { create("Player", "Mike", players) })
	local retrying: string? = check("A retried teleport", retried, true, RETRIED, 3)
	if retrying then
		return false, retrying
	end

	-- 4) Every try throwing ends the run once its tries run out
	local spent: Outcome = run(loaded, { "throw", "throw", "throw" }, false, { create("Player", "Mike", players) })
	local spending: string? = check("Tries that run out", spent, false, RAN_OUT, 3)
	if spending then
		return false, spending
	end

	return true, nil
end
