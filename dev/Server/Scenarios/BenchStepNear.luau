--[[
    The step benchmark's near rate run: S3 with anti-ESP's workers off then
    on, its near hidden pairs retested once a server tick in both halves,
    the workers put back after the run
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("near")
end
