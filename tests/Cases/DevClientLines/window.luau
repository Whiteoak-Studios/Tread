--[[
    A run's client lines: the event rated for the run, a window opened on a
    new label after the run's own opening, one line kept for each expected
    player, a missing one named, and the listener and attribute let go
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local CLIENT_LINES: string = "dev/Server/Bots/ClientLines.luau"
local ATTRIBUTE: string = "Case"
local WAIT: number = 0.1 -- Seconds the stop waits for the missing player's line
local RATE: { perSecond: number, burst: number } = { perSecond = 1, burst = 2 }
local STALE: string = "Case 0" -- A label no window of this run opens

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local workspace: any = dataModel:GetService("Workspace")

	local mike: any = create("Player", "Mike", dataModel:GetService("Players"))
	local guest: any = create("Player", "Guest", dataModel:GetService("Players"))

	-- Lune's Players has no GetPlayers, so the module's game answers Players with the two real players in
	local players: any = {
		GetPlayers = function (_: any): { any }
			return { mike, guest }
		end,
	}

	local place: any = {
		GetService = function (_: any, name: string): any
			if name == "Players" then
				return players
			end

			return dataModel:GetService(name)
		end,
	}

	-- The dev scope's server module standing in, keeping the rate set and the listener bound
	local rated: string = ""
	local listener: any = nil
	local stopped: boolean = false
	local network: any = {
		rate = function (name: string, perSecond: number, burst: number)
			rated = `{name} {perSecond} {burst}`
		end,

		clientCost = {
			on = function (callback: any): () -> ()
				listener = callback

				return function ()
					stopped = true
				end
			end,
		},
	}

	local files: { [any]: string } = { [server.Bots.ClientLines] = CLIENT_LINES }
	local results: { [any]: any } = { [shared.Network.Server] = network, [server.Bots.Run] = {} }
	local ClientLines: any = Kit.loader(place, files, results, loaded.require)(server.Bots.ClientLines)

	-- 1) Listening rates the event for the run
	local window: any = ClientLines.new(ATTRIBUTE, WAIT)
	local stop: () -> () = ClientLines.listen(window, RATE)
	if rated ~= `clientCost {RATE.perSecond} {RATE.burst}` or listener == nil then
		return false, `Listening rated {rated} and bound {listener}, not clientCost at its rate with a listener`
	end

	-- 2) The window opens after the run's own opening, on a new label the attribute holds
	local entries: { any } = { "entry" }
	local opened: { any }? = nil
	local probe: any = ClientLines.probe(window, function (given: { any })
		opened = given
	end)

	probe.start(entries)
	local label: any = window.label
	local set: any = workspace:GetAttribute(ATTRIBUTE)
	if opened ~= entries or type(label) ~= "string" or set ~= label then
		return false, `The window opened on {label} with {set} set, its opening handed {opened}`
	end

	-- 3) One line kept for each expected player, a second one and a stale label's left out, and the silent one named
	listener(mike, label, true, "Mike's line")
	listener(mike, label, true, "Mike's second line")
	listener(guest, STALE, true, "Guest's stale line")

	local line: string = probe.stop({})
	local missing: string = `Guest sent no report within {WAIT} s`
	local wanted: string = `{label}: Mike's line; {missing}`
	if line ~= wanted then
		return false, `The window gave "{line}", not "{wanted}"`
	elseif table.concat(window.problems, " | ") ~= `{label}: {missing}` then
		return false, `The window's problems are {table.concat(window.problems, " | ")}, not the missing line alone`
	elseif window.label ~= nil or workspace:GetAttribute(ATTRIBUTE) ~= nil then
		return false, `The stop left the label {window.label} and the attribute {workspace:GetAttribute(ATTRIBUTE)}`
	end

	-- 4) Stopping lets the listener go and clears the attribute whatever a run left on it
	workspace:SetAttribute(ATTRIBUTE, label)
	stop()
	local left: any = workspace:GetAttribute(ATTRIBUTE)
	if not stopped or left ~= nil then
		return false, `The stop let the listener go: {stopped}, and left the attribute {left}`
	end

	return true, nil
end
