--[[
    The step benchmark's NPC budget run: S4Npcs on the plaza's fixed ground,
    before then after, with the NPCs' budget flipped alone and every other
    lever as the server has it in both halves
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)

return function (): (boolean, string | nil)
	return BenchStep("npcs")
end
