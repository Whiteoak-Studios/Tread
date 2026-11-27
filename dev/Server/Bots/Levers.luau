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

local AntiEsp = require(Packages.Tread.Server.AntiEsp)
local Characters = require(Packages.Tread.Server.Characters)
local Commands = require(Packages.Tread.Server.Commands)
local Npcs = require(Packages.Tread.Server.Npcs)
local Relay = require(Packages.Tread.Server.Relay)
local Tick = require(Packages.Tread.Server.Tick)

local Config = require(ServerScriptService.Server.Bots.Config)
local Game = require(ServerScriptService.Server.Game)
local Run = require(ServerScriptService.Server.Bots.Run)

local BEFORE: Config.Bands = require(ServerScriptService.Server.Bots.Config).step.before
local SEPARATOR: string = ", " -- Between the levers in a line

-- One lever: its name, the step that added it, 0 for one from before the build, and how it is read and set
export type Lever = {
	name: string,
	session: number,
	live: boolean, -- false for a lever fixed as the server boots
	alone: boolean?, -- true for a live lever its session's flip leaves as it is, set only when flipped by its name
	get: () -> boolean,
	set: ((on: boolean) -> ())?, -- nil for a boot lever
}

-- The settings the dev game started Tread's server with, which a boot lever and the relay's levers read
local function settings(): Tread.ServerSettings
	local _, _, started: Tread.ServerSettings = Game.get()

	return started
end

local function onOff(on: boolean): string
	return on and "on" or "off"
end

-- Whether the relay's distance bands and edges are the ones the dev server was started with, value for value
local function startedBands(): boolean
	local tiers: { read bands: { Config.Band }, read edges: { Config.Edge } } = settings().tiers
	local bands: { Config.Band }, edges: { Config.Edge } = Relay.bands()
	if #bands ~= #tiers.bands or #edges ~= #tiers.edges then
		return false
	end

	for index: number, band: Config.Band in tiers.bands do
		if bands[index].aim ~= band.aim or bands[index].floor ~= band.floor then
			return false
		end
	end

	for index: number, edge: Config.Edge in tiers.edges do
		if edges[index].enter ~= edge.enter or edges[index].leave ~= edge.leave then
			return false
		end
	end

	return true
end

-- Sets the relay's distance bands to the dev server's own when on, and to the before half's when off
local function setBands(on: boolean)
	if not on then
		Relay.setBands(BEFORE.bands, BEFORE.edges)

		return
	end

	local tiers: { read bands: { Config.Band }, read edges: { Config.Edge } } = settings().tiers
	Relay.setBands(tiers.bands, tiers.edges)
end

-- The value a key of the dev server's settings holds, which a lever's on sets, refused when the server started without
local function started<T>(value: T?, key: string): T
	if value == nil then
		error(`the dev server started with no {key} to set`, 0)
	end

	return value :: T
end

-- Sets the relay's crowd cap to the dev server's own when on, refused when it started with none, and to none when off
local function setCrowd(on: boolean)
	Relay.setCrowd(on and started(settings().tiers.crowd, "tiers.crowd") or nil)
end

-- Sets anti-ESP's slice whole when on, refused when the dev server started without antiEsp.whole, and not when off
local function setWhole(on: boolean)
	if on and settings().antiEsp.whole ~= true then
		error("the dev server started with no antiEsp.whole to set", 0)
	end

	AntiEsp.useWhole(on)
end

-- Sets the NPCs' budget to the dev server's own when on, refused when it started with none, and to none when off
local function setNpcBudget(on: boolean)
	Npcs.setBudget(on and started(settings().npcs.budget, "npcs.budget") or nil)
end

-- Sets relay.budget to the dev server's own when on, refused when it started with none, and to none when off, which
-- the relay refuses while the far rate under load is set
local function setRelayBudget(on: boolean)
	local relay: { read budget: number? }? = settings().relay
	Relay.setBudget(on and started(relay and relay.budget, "relay.budget") or nil)
end

-- Sets the far rate under load to the dev server's own when on, refused when it started with none or the relay holds
-- no budget, and to none when off
local function setUnderLoad(on: boolean)
	Relay.setUnderLoad(on and started(settings().tiers.underLoad, "tiers.underLoad") or nil)
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

		{ name = "bands", session = 2, live = true, get = startedBands, set = setBands },

		{
			name = "crowdCap",
			session = 2,
			live = true,
			get = function (): boolean
				return Relay.crowd() ~= nil
			end,
			set = setCrowd,
		},

		{ name = "antiEspWorkers", session = 2, live = true, get = AntiEsp.workersOn, set = AntiEsp.useWorkers },

		-- Flipped only by the memory run, since the step loads can't show it
		{
			name = "verdictMemory",
			session = 2,
			live = true,
			alone = true,
			get = AntiEsp.memoryOn,
			set = AntiEsp.useMemory,
		},

		-- Flipped only by the split run, so the frame caps' halves never mix the split into what they show
		{ name = "stageSplit", session = 3, live = true, alone = true, get = Tick.splitOn, set = Tick.useSplit },

		{ name = "antiEspWhole", session = 3, live = true, get = AntiEsp.wholeOn, set = setWhole },

		{
			name = "npcBudget",
			session = 3,
			live = true,
			get = function (): boolean
				return Npcs.budget() ~= nil
			end,
			set = setNpcBudget,
		},

		-- Before the far rate under load, which needs it set: a flip and a restore set the list's levers on forwards
		-- and off backwards
		{
			name = "relayBudget",
			session = 3,
			live = true,
			get = function (): boolean
				return Relay.budget() ~= nil
			end,
			set = setRelayBudget,
		},

		{
			name = "farUnderLoad",
			session = 3,
			live = true,
			get = function (): boolean
				return Relay.underLoad() ~= nil
			end,
			set = setUnderLoad,
		},
	} :: { Lever },
}

-- The list's indices in the order its levers are set to a state: forwards to on and backwards to off, so a lever that
-- needs one before it set finds it set, and that one is cleared after it
local function order(on: boolean): (number, number, number)
	if on then
		return 1, #Levers.list, 1
	end

	return #Levers.list, 1, -1
end

-- Sets a lever as on says, adding a line that names it and what its setter threw to refused when it refuses
local function attempt(lever: Lever, set: (on: boolean) -> (), on: boolean, refused: { string })
	local done: boolean, failure: any = pcall(set, on)
	if not done then
		table.insert(refused, `{lever.name} refused {onOff(on)}: {failure}`)
	end
end

--[[
    Reads a lever's state and sets it as on says, both under one pcall, and
    gives the state it read, or nil when its getter threw, which leaves it
    unset. A line naming the lever and what its getter or setter threw
    joins refused
--]]

local function flipOne(lever: Lever, set: (on: boolean) -> (), on: boolean, refused: { string }): boolean?
	local read: boolean = false
	local found: boolean = false
	local done: boolean, failure: any = pcall(function ()
		found = lever.get()
		read = true
		set(on)
	end)

	if not read then
		table.insert(refused, `{lever.name} refused a read: {failure}`)

		return nil
	elseif not done then
		table.insert(refused, `{lever.name} refused {onOff(on)}: {failure}`)
	end

	return found
end

--[[
    Sets every live lever the given step added on or off but those marked
    alone, or, given only, the one live lever of that name whatever its
    step, in the list's order to on and the reverse to off, and gives the
    state each was in before, by its name, for restore to put back, with a
    line for each whose getter or setter refused and one when no live lever
    has that name. It never throws, and every other lever is left as it is
--]]

function Levers.flip(session: number, on: boolean, only: string?): ({ [string]: boolean }, { string })
	local states: { [string]: boolean } = {}
	local refused: { string } = {}
	local named: boolean = false -- Whether a live lever has the name given
	local first: number, last: number, step: number = order(on)

	for index: number = first, last, step do
		local lever: Lever = Levers.list[index]
		local set: ((on: boolean) -> ())? = lever.set
		local chosen: boolean = lever.session == session and lever.alone ~= true
		if only then
			chosen = lever.name == only
		end

		if lever.live and chosen and set then
			named = true

			local state: boolean? = flipOne(lever, set, on, refused)
			if state ~= nil then
				states[lever.name] = state
			end
		end
	end

	if only and not named then
		table.insert(refused, `no live lever is named {only}`)
	end

	return states, refused
end

--[[
    Puts each lever the states name back in the state given, as flip found
    it, the off states first in the list's reverse order and then the on
    states in its order, with a line for each that refused
--]]

function Levers.restore(states: { [string]: boolean }): { string }
	local refused: { string } = {}

	for _, on: boolean in { false, true } do
		local first: number, last: number, step: number = order(on)

		for index: number = first, last, step do
			local lever: Lever = Levers.list[index]
			local set: ((on: boolean) -> ())? = lever.set
			if states[lever.name] == on and set then
				attempt(lever, set, on, refused)
			end
		end
	end

	return refused
end

-- Every lever in one line: the step that added it, whether it is live or boot, and its state now
function Levers.line(): string
	local parts: { string } = {}

	for _, lever: Lever in Levers.list do
		local kind: string = lever.live and "live" or "boot"
		table.insert(parts, `{lever.name} (session {lever.session}, {kind}) {onOff(lever.get())}`)
	end

	return table.concat(parts, SEPARATOR)
end

return Levers
