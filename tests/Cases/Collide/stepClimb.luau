--[[
    A walk into the 0.5-stud step climbs it through the step up and goes on
    along its top a skin above it
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("stepClimb")
end
