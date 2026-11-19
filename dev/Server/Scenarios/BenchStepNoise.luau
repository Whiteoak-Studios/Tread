--[[
    The step benchmark's noise run: its loads and timing with no lever
    flipped in either half, to show how far two identical halves of one
    load differ on one server
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep(true)
end
