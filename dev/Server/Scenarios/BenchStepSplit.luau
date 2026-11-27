--[[
    The step benchmark's split run: its three loads in their halves' order
    with the relay's split by stage flipped alone, off in one half and on in
    the other, and the frame caps as the server has them in both
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("split")
end
