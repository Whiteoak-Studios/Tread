--[[
    A top one quantum past the game's reach over the ground last stood on
    is no ledge to mantle, so the jump press jumps
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("pastReach")
end
