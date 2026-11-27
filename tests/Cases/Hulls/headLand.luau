--[[
    A body falling onto another's head lands on its hull top, and Collide.move
    gives back the body it stands on
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("headLand")
end
