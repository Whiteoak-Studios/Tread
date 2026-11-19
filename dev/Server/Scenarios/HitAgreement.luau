--[[
    G7's hit agreement: the dev client fires fixture shots at bots in each
    configured case, and each case's line pairs its own view of every shot
    with what the server's fixture struck
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Hits = require(ServerScriptService.Server.Hits)

local CASES: { Hits.Case } = require(ServerScriptService.Server.Config.Hits).cases

return function (): (boolean, string | nil)
	return Hits.run(CASES)
end
