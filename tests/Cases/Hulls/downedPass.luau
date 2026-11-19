--[[
    A downed body's hull blocks no one, so a walk passes straight through it
    and ends where its move alone takes it
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("downedPass")
end
