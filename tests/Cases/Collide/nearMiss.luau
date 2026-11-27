--[[
    A move that would end inside a skin of the wall without reaching it still
    stops a skin short, since each slide's cast reaches past its move
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("nearMiss")
end
