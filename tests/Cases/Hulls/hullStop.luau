--[[
    Another live body's hull stops a walk a skin short of it, as the world's
    geometry does, so players block each other
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("hullStop")
end
