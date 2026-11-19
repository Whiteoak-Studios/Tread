--[[
    Benchmark scenario S0, an empty server, run for each of the program's
    seeds with Tread's stats printed each second of the window
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S0", FULL)
end
