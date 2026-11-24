--[[
    The step benchmark's noise run: its loads and timing with the session's
    levers on in both halves and no flip between them, to show how far two
    identical after halves of one load differ on one server
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("noise")
end
