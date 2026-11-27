--[[
    G8's doorway and window check over every marker in the configured
    folders: a target just inside each opening and a viewer out along it,
    failing a marker whose visible target its viewer isn't sent
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Reveals = require(ServerScriptService.Server.Reveals)

return function (): (boolean, string | nil)
	return Reveals.openings(nil)
end
