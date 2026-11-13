--[[
    Benchmark scenario S3, the city mix of 60 bots from the plaza and 89 on
    the map, run for each seed with Tread's stats printed each second
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S3", FULL)
end
