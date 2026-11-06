--[[
    A top exactly the game's reach over the ground last stood on is mantled
    on a jump press, straight up beside the face and then ahead onto it,
    ending there standing once the game's mantle time has run
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("exactReach")
end
