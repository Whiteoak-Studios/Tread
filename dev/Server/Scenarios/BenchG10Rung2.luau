--[[
    G10's load at the ladder's rung that idles every NPC, 299 bots and 32
    NPCs built asleep, run for each seed with Tread's stats printed each
    second and no pass line
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full
local CLOSING: string = "Bots G10: the ladder's Actor and validate-only rungs run on branches of their own, not here"
local SEPARATOR: string = "; " -- Between the rung's lines and the closing one

return function (): (boolean, string | nil)
	local passed: boolean, line: string = Run.run("G10Rung2", FULL)
	print(CLOSING)

	return passed, `{line}{SEPARATOR}{CLOSING}`
end
