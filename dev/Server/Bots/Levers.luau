--[[
    The levers the step benchmark's halves are told apart by: each with the
    step of the performance build that added it, and whether a run sets it
    live or it is fixed as the server boots, which a run only reads
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Characters = require(Packages.Tread.Server.Characters)
local Commands = require(Packages.Tread.Server.Commands)

local Game = require(ServerScriptService.Server.Game)
local Run = require(ServerScriptService.Server.Bots.Run)

local SEPARATOR: string = ", " -- Between the levers in a line

-- One lever: its name, the step that added it, 0 for one from before the build, and how it is read and set
export type Lever = {
	name: string,
	session: number,
	live: boolean, -- false for a lever fixed as the server boots
	get: () -> boolean,
	set: ((on: boolean) -> ())?, -- nil for a boot lever
}

-- The settings the dev game started Tread's server with, which a boot lever reads
local function settings(): Tread.ServerSettings
	local _, _, started: Tread.ServerSettings = Game.get()

	return started
end

local Levers = {
	-- A lever a step adds is one entry, and a live one's seam in src takes a boolean, with a getter beside it
	list = {
		{ name = "lazyDecode", session = 1, live = true, get = Commands.lazyOn, set = Commands.useLazy },
		{ name = "ownerChecks", session = 1, live = true, get = Characters.checksOn, set = Characters.useChecks },

		{
			name = "relayWorkers",
			session = 0,
			live = false,
			get = function (): boolean
				return Run.workers() > 0
			end,
		},

		{
			name = "relayClocks",
			session = 1,
			live = false,
			get = function (): boolean
				local relay: { read clocks: boolean? }? = settings().relay

				return relay ~= nil and relay.clocks == true
			end,
		},

		{
			name = "outOfView",
			session = 0,
			live = false,
			get = function (): boolean
				return settings().tiers.outOfView ~= nil
			end,
		},

		{
			name = "changes",
			session = 0,
			live = false,
			get = function (): boolean
				local relay: { read changes: boolean? }? = settings().relay

				return relay ~= nil and relay.changes == true
			end,
		},
	} :: { Lever },
}

--[[
    Sets every live lever the given step added on or off, and gives the
    state each was in before, by its name, for restore to put back. A boot
    lever and another step's are left as they are
--]]

function Levers.flip(session: number, on: boolean): { [string]: boolean }
	local states: { [string]: boolean } = {}

	for _, lever: Lever in Levers.list do
		local set: ((on: boolean) -> ())? = lever.set
		if lever.live and lever.session == session and set then
			states[lever.name] = lever.get()
			set(on)
		end
	end

	return states
end

-- Puts each lever the states name back in the state given, as flip found it
function Levers.restore(states: { [string]: boolean })
	for _, lever: Lever in Levers.list do
		local state: boolean? = states[lever.name]
		local set: ((on: boolean) -> ())? = lever.set
		if state ~= nil and set then
			set(state)
		end
	end
end

-- Every lever in one line: the step that added it, whether it is live or boot, and its state now
function Levers.line(): string
	local parts: { string } = {}

	for _, lever: Lever in Levers.list do
		local kind: string = lever.live and "live" or "boot"
		local state: string = lever.get() and "on" or "off"
		table.insert(parts, `{lever.name} (session {lever.session}, {kind}) {state}`)
	end

	return table.concat(parts, SEPARATOR)
end

return Levers
