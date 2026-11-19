--[[
    Benchmark scenario S10 for G9, S3's city mix with four parked moderators
    spectating city bots, run for each seed with the withheld bytes, each
    moderator's lines and the recording taps' cost printed after the window
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)
local Spectators = require(ServerScriptService.Server.Spectators)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full

return function (): (boolean, string | nil)
	return Run.run("S10", FULL, Spectators.probe(FULL))
end
