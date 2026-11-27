--[[
    G8's late reveals under its load, seed by seed: S3's layout with the
    city group sprinting, every real player and the first city bots watched
    with the exact test beside the window's stats
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Reveals = require(ServerScriptService.Server.Reveals)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Config.Reveals).full

return function (): (boolean, string | nil)
	return Run.run("G8", FULL, Reveals.probe())
end
