--[[
    The bots on the dev game's running server: each one's Volt bot, client
    side, character and program, the stage after the relay they all send
    from, and their removal
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)
local Volt = require(Packages.Volt)

local Bot = require(ServerScriptService.Server.Bots.Bot)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Side = require(ServerScriptService.Server.Bots.Side)

local STAGE: string = require(ServerScriptService.Server.Bots.Config).stage
local DELAY: number = require(ServerScriptService.Server.Bots.Config).delay
local FIELDS: { [string]: any } = require(ServerScriptService.Server.Bots.Config).fields

-- One bot on the server, from its build to its removal
export type Entry = {
	volt: Volt.Bot,
	character: Tread.Character,
	bot: Bot.Bot,
	group: string, -- The group of its scenario it belongs to
}

-- What a bot is built from
export type Plan = {
	name: string,
	group: string,
	at: CFrame, -- Where its feet go, facing along the look
	steer: Programs.Steer?, -- nil for a bot that sends only what it is handed
	faults: Bot.Faults?,
	seed: number,
}

type Listener = { callback: (tick: number) -> (), connected: boolean }

local Entries: { Entry } = {} -- Every bot built and not yet removed, in the order built
local Listeners: { Listener } = {}
local Context: Bot.Context? = nil -- What every bot encodes with, made once a server with the stage
local Stall: number = 0 -- Seconds the next tick holds the server still for, 0 for none

local Fleet = {}

-- Runs where a bot's tick raised its error, so its warning keeps the stack
local function warnBot(message: any)
	warn(`A bot's tick threw, and the other bots still sent: {debug.traceback(tostring(message), 2)}`)
end

local function warnListener(message: any)
	warn(`A bot stage listener threw, and the others still ran: {debug.traceback(tostring(message), 2)}`)
end

--[[
    The stage: every bot's tick, each under its own xpcall so one that
    throws stops none after it, then each listener, then any stall asked
    for, held by a loop that ends on its own deadline
--]]

local function run(tick: number)
	for _, entry: Entry in Entries do
		xpcall(entry.bot.tick, warnBot, entry.bot, tick)
	end

	for _, listener: Listener in table.clone(Listeners) do
		if listener.connected then
			xpcall(listener.callback, warnListener, tick)
		end
	end

	if Stall > 0 then
		local ends: number = os.clock() + Stall
		Stall = 0

		while os.clock() < ends do
			continue
		end
	end
end

--[[
    What every bot of the running server encodes with, made with the stage
    the first time, which lives as long as the server, since a stage stays
--]]

function Fleet.start(): Bot.Context
	local made: Bot.Context? = Context
	if made then
		return made
	end

	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local context: Bot.Context = Bot.context(shared, DELAY, FIELDS)

	-- After the relay, so a command a bot makes reaches the next tick's decode as a player's arriving between does
	server:addStage(STAGE, "relay", run)
	Context = context

	return context
end

--[[
    Builds a bot: a Volt bot, its client side of Tread's scope, its
    character where the plan puts it and its program. A step that fails
    takes back what the steps before it made, then passes the error on
--]]

function Fleet.add(plan: Plan): Entry
	local context: Bot.Context = Fleet.start()
	local server: Tread.Server = Game.get()
	local volt: Volt.Bot = Volt.addBot(plan.name)

	local sided: boolean, network: any = pcall(Side, volt)
	if not sided then
		Volt.removeBot(volt)
		error(network, 0)
	end

	local created: boolean, character: any = pcall(server.create, server, volt, plan.at)
	if not created then
		Volt.removeBot(volt)
		error(character, 0)
	end

	local made: boolean, bot: any = pcall(Bot.new, network, context, plan.steer, plan.faults, plan.seed)
	if not made then
		character:destroy()
		Volt.removeBot(volt)
		error(bot, 0)
	end

	local entry: Entry = { volt = volt, character = character, bot = bot, group = plan.group }
	table.insert(Entries, entry)

	return entry
end

-- Every bot built and not yet removed, the fleet's own list, which a reader leaves as it is
function Fleet.entries(): { Entry }
	return Entries
end

--[[
    Removes every bot: its program stopped, its character destroyed and its
    Volt bot taken away, each under its own pcall, so one that fails stops
    none of the rest. Gives what failed, empty when nothing did
--]]

function Fleet.clear(): { string }
	local problems: { string } = {}

	for _, entry: Entry in Entries do
		local name: string = entry.volt.Name
		local stopped: boolean, stopFailure: any = pcall(entry.bot.destroy, entry.bot)
		local ended: boolean, endFailure: any = pcall(entry.character.destroy, entry.character)
		local removed: boolean, removeFailure: any = pcall(Volt.removeBot, entry.volt)

		if not stopped then
			table.insert(problems, `{name}'s program did not stop: {stopFailure}`)
		end

		if not ended then
			table.insert(problems, `{name}'s character was not destroyed: {endFailure}`)
		end

		if not removed then
			table.insert(problems, `{name}'s Volt bot was not removed: {removeFailure}`)
		end
	end

	table.clear(Entries)

	return problems
end

--[[
    Calls back after every bot has sent on each tick, with the tick as the
    server counts it, unwrapped. Returns the closure that disconnects it
--]]

function Fleet.onTick(callback: (tick: number) -> ()): () -> ()
	local listener: Listener = { callback = callback, connected = true }
	table.insert(Listeners, listener)

	return function ()
		listener.connected = false

		local index: number? = table.find(Listeners, listener)
		if index then
			table.remove(Listeners, index)
		end
	end
end

-- Holds the server still for that many seconds on the next tick, as a hitch on a live server does
function Fleet.stall(seconds: number)
	Stall = seconds
end

return Fleet
