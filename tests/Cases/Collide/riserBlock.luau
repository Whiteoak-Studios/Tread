--[[
    The 1-stud riser is past the step height, so a walk into it stops a skin
    short of its side and gains no height
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("riserBlock")
end
