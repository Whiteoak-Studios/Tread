--[[
    A step up whose landing finds ground under half a skin below is refused
    for the plain slide, so the ledge just past the step height is not climbed
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("ledgeSliver")
end
