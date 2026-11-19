--[[
    Benchmark scenario S9 for G9, S3's city mix with 2,000 sleepers lying
    over the city and the map, run for each seed with Tread's stats printed
    each second, anti-ESP's lying-pair counts among them once it gives them
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S9", FULL)
end
