--[[
    Benchmark scenario S2, 149 bots roaming the map around the viewer, run
    for each of the program's seeds with Tread's stats printed each second
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S2", FULL)
end
