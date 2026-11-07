--[[
    Benchmark scenario S5, a join storm of 149 bots all joining as the
    window opens, run for each seed with Tread's stats printed each second
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S5", FULL)
end
