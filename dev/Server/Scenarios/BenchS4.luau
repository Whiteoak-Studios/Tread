--[[
    Benchmark scenario S4, a fight of 149 bots roaming 100 studs around the
    viewer, run for each seed with Tread's stats printed each second
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S4", FULL)
end
