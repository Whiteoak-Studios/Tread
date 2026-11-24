--[[
    The dev place's switch for the relay's split by stage: a player's ask,
    refused while a live run goes, sets Workspace's attribute, and one
    watcher hands its every change to the tick loop, whoever made it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Tick = require(Packages.Tread.Server.Tick)

local ATTRIBUTE: string = require(ServerScriptService.Server.Config.BotPanel).splitAttribute
local REASON_BYTES: number = require(ServerScriptService.Server.Config.BotPanel).reasonBytes
local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.BotPanel).rates.split

type Key = Player | Volt.Bot

local LiveRun: (() -> string?)? = nil -- The live panel's run going, from the start

local Split = {}

--[[
    What the ghosts' label says: the split's state first, so a cut to the
    label's bound never drops it, then the relay workers the server
    started, so it changes only when the split is turned on or off
--]]

function Split.label(on: boolean, workers: number): string
	local state: string = on and "on" or "off"

	return `split {state}, {workers} relay workers`
end

-- The attribute as it stands, handed to the tick loop, anything but true leaving the split off as the boot reads it
local function changed()
	Tick.useSplit(Workspace:GetAttribute(ATTRIBUTE) == true)
end

--[[
    A player's ask for the split on or off: refused with the reason while
    a live run measures the server, as the panel refuses a spawn, and set
    on the attribute otherwise, whose watcher turns the tick loop's split
--]]

local function ask(key: Key, on: boolean)
	-- A Volt bot fires none of the dev scope's events, so whoever asked is a player
	local player: Player = key :: Player

	local running: string? = nil
	local liveRun: (() -> string?)? = LiveRun
	if liveRun then
		running = liveRun()
	end

	if running then
		local reason: string = `{running} is running on the live panel, so the split stays as it is until it ends`
		Network.botRefused.fire(player, string.sub(reason, 1, REASON_BYTES))

		return
	end

	Workspace:SetAttribute(ATTRIBUTE, on)
end

--[[
    Binds the asks at the dev game's own rate, hands the tick loop the
    attribute as it stands, then watches it, so a change from Studio, a
    check or an ask reaches the loop alike. running gives the live panel's
    run going. It runs once a server, and its listeners live as long as
    the server
--]]

function Split.start(running: () -> string?)
	if LiveRun then
		error("Split.start runs once a server, and it has already run", 2)
	end

	LiveRun = running

	Network.rate("botSplit", RATE.perSecond, RATE.burst)
	Network.botSplit.on(ask)

	changed()
	Workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(changed)
end

return Split
