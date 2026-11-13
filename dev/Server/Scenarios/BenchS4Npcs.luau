--[[
    Benchmark load S4Npcs for G3, S4's 150-player fight with 32 awake NPCs
    roaming it too, run for each seed with Tread's stats printed each second
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S4Npcs", FULL)
end
