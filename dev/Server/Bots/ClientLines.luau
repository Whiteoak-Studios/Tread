--[[
    The real players' lines beside a bot run's windows: each window opens
    with a new label on a Workspace attribute and ends by clearing it, then
    waits for every real player's line over the dev scope's clientCost
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Run = require(ServerScriptService.Server.Bots.Run)

local SEPARATOR: string = "; " -- Between the players' lines

type Key = Player | Volt.Bot

-- One run's windows, its label nil before one opens and once its wait for the lines ends
export type Window = {
	attribute: string, -- The Workspace attribute its label is set on, which the clients watch
	wait: number, -- Seconds after a window ends it waits for each real player's line
	label: string?,
	expected: { Player }, -- The real players in as it opened
	lines: { [Player]: string }, -- Each one's line, as their report gave it
	problems: { string }, -- Across every window of the run
}

local Windows: number = 0 -- The windows opened on this server, so each label is new and a late report matches none

local ClientLines = {}

-- A run's windows on the attribute given, before any opens
function ClientLines.new(attribute: string, wait: number): Window
	return { attribute = attribute, wait = wait, label = nil, expected = {}, lines = {}, problems = {} }
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

--[[
    Binds the dev scope's clientCost at the run's rate and hears each report
    into the window, giving what stops hearing and clears the attribute,
    which the run calls whatever it did
--]]

function ClientLines.listen(window: Window, rate: { perSecond: number, burst: number }): () -> ()
	-- Bound for the run alone, and a report queued since the last run carries a label no window waits on
	Network.rate("clientCost", rate.perSecond, rate.burst)
	local stopListening: () -> () = Network.clientCost.on(
		function (key: Key, label: string, measured: boolean, line: string)
			heard(window, key, label, measured, line)
		end
	)

	return function ()
		stopListening()
		Workspace:SetAttribute(window.attribute, nil)
	end
end

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
    The probe beside each of the run's windows: it opens with anything the
    run sets first and a new label on the attribute, and stops by clearing
    it, then waits for each real player's report until its own deadline,
    giving every one's line or what kept it
--]]

function ClientLines.probe(window: Window, opening: ((entries: { any }) -> ())?): Run.Probe
	return {
		start = function (entries: { any })
			if opening then
				opening(entries)
			end

			Windows += 1
			window.label = `{window.attribute} {Windows}`
			window.expected = Players:GetPlayers()
			table.clear(window.lines)
			Workspace:SetAttribute(window.attribute, window.label)
		end,

		stop = function (_: { [string]: { number } }): string
			Workspace:SetAttribute(window.attribute, nil)

			local label: string? = window.label
			if not label then
				return "no window was open"
			end

			-- Each report leaves its client once the clear reaches it, so the wait runs until its own deadline at most
			local deadline: number = os.clock() + window.wait
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
					local missing: string = `{player.Name} sent no report within {window.wait} s`
					table.insert(lines, missing)
					table.insert(window.problems, `{label}: {missing}`)
				end
			end

			return `{label}: {table.concat(lines, SEPARATOR)}`
		end,
	}
end

return ClientLines
