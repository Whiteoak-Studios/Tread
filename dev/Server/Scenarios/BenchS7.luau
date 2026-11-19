--[[
    Benchmark scenario S7, cheater bots of each kind among honest ones and a
    server stall, run for each seed with every group's reports printed
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S7", FULL)
end
