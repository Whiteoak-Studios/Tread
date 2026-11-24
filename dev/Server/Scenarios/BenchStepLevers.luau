--[[
    The step benchmark's levers run: each of session 2's levers flipped
    alone on a load of its own, the others and the frame caps held off for
    the run and put back after it
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("levers")
end
