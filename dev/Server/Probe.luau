--[[
    The scaffold probe's server half: runs the step fixture on the server and
    returns its numbers as hex, one a line, for Lune's run to compare
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Probe = require(ServerScriptService.Fixtures.Probe)

return function (flip: boolean): string
	return Probe.encode(Probe.run(flip))
end
