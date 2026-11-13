--[[
    G5's client cost: every real player on G5's team and set down beside its
    first bot, each seed's window measured on every real client, and each
    client's line of Tread's remote-character work a frame printed
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Config = require(ServerScriptService.Server.Bots.Config)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full
local TEAM: number? = require(ServerScriptService.Server.Bots.Config).scenarios.G5.groups[1].team
local ATTRIBUTE: string = require(ServerScriptService.Server.Config.ClientCost).attribute
local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.ClientCost).rate
local WAIT: number = require(ServerScriptService.Server.Config.ClientCost).wait
local BESIDE: number = require(ServerScriptService.Server.Config.ClientCost).beside
local LIFT: number = require(ServerScriptService.Server.Config.ClientCost).lift
local LOAD: string = "G5" -- The bot harness's load each window is measured in
local SEPARATOR: string = "; " -- Between the parts of one line

type Key = Player | Volt.Bot

-- One window's reports, its label nil before it opens and once its wait for them ends
type Window = {
	label: string?,
	expected: { Player }, -- The real players in as it opened
	lines: { [Player]: string }, -- Each one's line, as their report gave it
	problems: { string }, -- Across every window of the run
}

local Windows: number = 0 -- The windows opened on this server, so each label is new and a late report matches none

-- Whether every real player the window waits on and still in has reported
local function reported(window: Window): boolean
	for _, player: Player in window.expected do
		if player.Parent ~= nil and not window.lines[player] then
			return false
		end
	end

	return true
end

--[[
    A client's report, kept when it is for the window waiting, from a real
    player it waits on, and their first for it. A report its client could
    not measure is a problem
--]]

local function heard(window: Window, key: Key, label: string, measured: boolean, line: string)
	-- A Volt bot fires none of the dev scope's events, so whoever sent it is a player
	local player: Player = key :: Player
	if label ~= window.label or not table.find(window.expected, player) or window.lines[player] then
		return
	end

	window.lines[player] = line

	if not measured then
		table.insert(window.problems, `{player.Name}'s client did not measure {label}: {line}`)
	end
end

-- Sets every real player holding a character down beside the first bot built, each a further step along X
local function setDown(entries: { any })
	local first: Fleet.Entry? = entries[1]
	if not first then
		error(`{LOAD} built no bot to set the real players down beside`, 0)
	end

	local feet: Vector3 = first.character:getState().root
	for index: number, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			character:teleport(CFrame.new(feet + Vector3.new(BESIDE * index, LIFT, 0)))
		end
	end
end

--[[
    The probe beside each seed's window: it opens with the real players set
    down and a new label on the attribute, and stops by clearing it, then
    waits for each real player's report until its own deadline, giving
    every one's line or what kept it
--]]

local function probeOf(window: Window): Run.Probe
	return {
		start = function (entries: { any })
			setDown(entries)

			Windows += 1
			window.label = `{ATTRIBUTE} {Windows}`
			window.expected = Players:GetPlayers()
			table.clear(window.lines)
			Workspace:SetAttribute(ATTRIBUTE, window.label)
		end,

		stop = function (_: { [string]: { number } }): string
			Workspace:SetAttribute(ATTRIBUTE, nil)

			local label: string? = window.label
			if not label then
				return "no window was open"
			end

			-- Each report leaves its client once the clear reaches it, so the wait runs until its own deadline at most
			local deadline: number = os.clock() + WAIT
			while not reported(window) and os.clock() < deadline do
				RunService.Heartbeat:Wait()
			end

			window.label = nil

			local lines: { string } = {}
			for _, player: Player in window.expected do
				local line: string? = window.lines[player]
				if line then
					table.insert(lines, line)
				elseif player.Parent == nil then
					table.insert(lines, `{player.Name} left before reporting`)
				else
					local missing: string = `{player.Name} sent no report within {WAIT} s`
					table.insert(lines, missing)
					table.insert(window.problems, `{label}: {missing}`)
				end
			end

			return `{label}: {table.concat(lines, SEPARATOR)}`
		end,
	}
end

return function (): (boolean, string | nil)
	if TEAM == nil then
		return false, `{LOAD}'s first group names no team for the real players to share`
	end

	local teamed: { Tread.Character } = {}
	for _, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			character:setTeam(TEAM)
			table.insert(teamed, character)
		end
	end

	if #teamed == 0 then
		return false, "no real player has a character to measure the client cost on"
	end

	local window: Window = { label = nil, expected = {}, lines = {}, problems = {} }

	-- Bound for the run alone, and a report queued since the last run carries a label no window waits on
	Network.rate("clientCost", RATE.perSecond, RATE.burst)
	local stopListening: () -> () = Network.clientCost.on(
		function (key: Key, label: string, measured: boolean, line: string)
			heard(window, key, label, measured, line)
		end
	)

	local ran: boolean, passed: any, line: any = pcall(Run.run, LOAD, FULL, probeOf(window), nil)

	-- Everything it set goes, whatever the run did
	stopListening()
	Workspace:SetAttribute(ATTRIBUTE, nil)

	for _, character: Tread.Character in teamed do
		-- A character destroyed during the run has no team left to take back
		pcall(character.setTeam, character, nil)
	end

	if not ran then
		return false, `it threw: {passed}`
	elseif #window.problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(window.problems, SEPARATOR)}`
	end

	return passed, line
end
