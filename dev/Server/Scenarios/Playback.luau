--[[
    Records a bot's walk past another as a moderator's clip, sends it to a
    real player's client and waits for that client to play it, so a live
    run can check client:play
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Clips = require(ServerScriptService.Server.Clips)

return function (): (boolean, string | nil)
	return Clips.run()
end
