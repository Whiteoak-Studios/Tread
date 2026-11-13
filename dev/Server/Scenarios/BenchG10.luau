--[[
    Benchmark G10 at 300 players: 299 bots spread over the map with 32
    awake NPCs, run for each seed with Tread's stats printed each second
    and no pass line
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("G10", FULL)
end
