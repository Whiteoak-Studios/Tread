--[[
    The split's switch: its start hands the attribute to the tick loop, an
    ask sets the attribute and so the loop at its own rate, one during a
    live run is refused, and a change made to the attribute directly reaches
    the loop too. The ghosts' label names the state alone inside its bound
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SPLIT: string = "dev/Server/Split.luau"
local GOING: string = "BenchS3" -- The live run going where the case has one
local WORKERS: number = 4 -- The relay workers the dev place starts
local FITS: number = 9999999 -- The most workers whose label fits whole, past any count a server starts

type Callback = (...any) -> ()

--[[
    A Workspace standing in for the engine's, with its attributes and a
    changed signal for each, which fires only when the value changes, as
    the engine's does
--]]

local function workspaceStandIn(): any
	local attributes: { [string]: any } = {}
	local watchers: { [string]: { Callback } } = {}

	return {
		GetAttribute = function (_: any, name: string): any
			return attributes[name]
		end,

		SetAttribute = function (_: any, name: string, value: any)
			if attributes[name] == value then
				return
			end

			attributes[name] = value
			for _, callback: Callback in table.clone(watchers[name] or {}) do
				callback()
			end
		end,

		GetAttributeChangedSignal = function (_: any, name: string): any
			return {
				Connect = function (_: any, callback: Callback): any
					local list: { Callback } = watchers[name] or {}
					watchers[name] = list
					table.insert(list, callback)

					return {}
				end,
			}
		end,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local panelConfig: any = loaded.require(server.Config.BotPanel)
	local labelBytes: number = loaded.require(server.Config.Ghost).labelBytes
	local attribute: string = panelConfig.splitAttribute
	local Tick: any = loaded.require(dataModel:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local workspace: any = workspaceStandIn()
	local fakeGame: any = {
		GetService = function (_: any, name: string): any
			if name == "Workspace" then
				return workspace
			end

			return dataModel:GetService(name)
		end,
	}

	local listeners: { [string]: Callback } = {}
	local refused: { string } = {}
	local rated: { [string]: { number } } = {}
	local running: { string? } = { nil }

	local network: any = {
		rate = function (name: string, perSecond: number, burst: number)
			rated[name] = { perSecond, burst }
		end,

		botSplit = {
			on = function (callback: Callback): () -> ()
				listeners.botSplit = callback

				return function () end
			end,
		},

		botRefused = {
			fire = function (_: any, reason: string)
				table.insert(refused, reason)
			end,
		},
	}

	local results: { [any]: any } = { [shared.Network.Server] = network }
	local Split: any = Kit.loader(fakeGame, { [server.Split] = SPLIT }, results, loaded.require)(server.Split)

	-- 1) The start hands the attribute as it stands to the loop, and takes the asks at the panel's rate for them
	workspace:SetAttribute(attribute, true)
	Split.start(function (): string?
		return running[1]
	end)

	local rate: { number }? = rated.botSplit
	if not Tick.splitOn() then
		return false, `With {attribute} true at the start, the tick loop's split stayed off`
	elseif not rate or rate[1] ~= panelConfig.rates.split.perSecond or rate[2] ~= panelConfig.rates.split.burst then
		return false, "The split's asks took no rate or another rate than the bot panel's config gives them"
	end

	-- 2) An ask sets the attribute, and its watcher the tick loop, each way
	local player: any = roblox.Instance.new("Player")
	player.Name = "Asker"

	listeners.botSplit(player, false)
	if workspace:GetAttribute(attribute) ~= false or Tick.splitOn() then
		return false, `An ask for the split off left {attribute} {workspace:GetAttribute(attribute)} and the loop's on`
	end

	listeners.botSplit(player, true)
	if workspace:GetAttribute(attribute) ~= true or not Tick.splitOn() then
		return false, `An ask for the split on left {attribute} {workspace:GetAttribute(attribute)} and the loop's off`
	end

	-- 3) During a live run an ask is refused with its reason and changes nothing
	running[1] = GOING
	listeners.botSplit(player, false)
	running[1] = nil

	local reason: string = `{GOING} is running on the live panel, so the split stays as it is until it ends`
	if table.concat(refused, " | ") ~= reason then
		return false, `An ask during a live run was answered with: {table.concat(refused, " | ")}`
	elseif workspace:GetAttribute(attribute) ~= true or not Tick.splitOn() then
		return false, "An ask refused during a live run still turned the split off"
	end

	-- 4) A change made to the attribute directly, from Studio or a check, reaches the loop, anything but true as off
	workspace:SetAttribute(attribute, false)
	local direct: boolean = Tick.splitOn()
	workspace:SetAttribute(attribute, true)
	local back: boolean = Tick.splitOn()
	workspace:SetAttribute(attribute, "true")

	if direct or not back or Tick.splitOn() then
		return false,
			`Direct changes left the loop's split at {direct}, {back} and {Tick.splitOn()}, not false, true, false`
	end

	-- 5) The ghosts' label names the state alone, inside its bound for both states, the state before any cut
	local labels: { { got: string, text: string } } = {
		{ got = Split.label(true, WORKERS), text = `split on, {WORKERS} relay workers` },
		{ got = Split.label(false, WORKERS), text = `split off, {WORKERS} relay workers` },
	}

	for _, label: { got: string, text: string } in labels do
		if label.got ~= label.text then
			return false, `The ghosts' label read "{label.got}", not "{label.text}"`
		end
	end

	for _, on: boolean in { true, false } do
		local label: string = Split.label(on, FITS)
		if #label > labelBytes then
			return false, `The ghosts' label at {FITS} workers is {#label} bytes, past the {labelBytes} it carries`
		end
	end

	local cut: string = string.sub(Split.label(true, FITS * 10), 1, labelBytes)
	if string.sub(cut, 1, #"split on, ") ~= "split on, " then
		return false, `The ghosts' label cut to its bound read "{cut}", which drops the state`
	end

	return true, nil
end
