--[[
    A bot's client side of Tread's scope: Volt's client transport for the
    bot, and a fresh copy of Tread's generated client module started on it,
    so its packets come from the same writers a player's client runs
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local ClientModule = Packages.Tread.Network.Client :: ModuleScript

local SCOPE: string = require(ServerScriptService.Server.Bots.Config).scope

type Network = typeof(require(Packages.Tread.Network.Client))

--[[
    Connects a bot to Tread's scope and starts a client runtime for it on
    that transport. The generated module starts its runtime as it is
    required, through Volt.start with no transport, so for the one require
    of a fresh copy Volt.start is handed the bot's transport, then put back
--]]

return function (bot: Volt.Bot): Network
	-- Whiteoak TODO: start the copy on the bot's transport through Volt itself once Volt can start a generated
	-- module on a transport it is handed, a Volt task, in place of handing Volt.start the transport for one require
	local transport: Volt.Transport = Volt.connectBot(bot, SCOPE)
	local copy: ModuleScript = ClientModule:Clone()
	local start = Volt.start

	-- A server-only home while it loads, so no client ever sees the copy
	copy.Parent = ServerStorage

	Volt.start = function (schema: Volt.Schema, _: Volt.Transport?): Volt.Runtime
		return start(schema, transport)
	end

	local loaded: boolean, network: any = pcall(require, copy)
	Volt.start = start
	copy:Destroy()

	if not loaded then
		error(`{bot.Name}'s client side of {SCOPE} did not start: {network}`, 2)
	end

	return network
end
