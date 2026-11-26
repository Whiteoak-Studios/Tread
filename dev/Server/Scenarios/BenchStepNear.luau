--[[
    The step benchmark's near-rate run: S3 at the server's near rate then
    the raised one with anti-ESP's workers held off, then raised then the
    server's own with them held on, each put back after the run
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("near")
end
