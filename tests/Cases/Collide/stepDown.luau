--[[
    Walking off the step's far edge, the ground snap follows the ground down
    to the floor and the body stays on the ground
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("stepDown")
end
