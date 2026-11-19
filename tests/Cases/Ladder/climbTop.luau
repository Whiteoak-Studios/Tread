--[[
    Walking into a ladder's box while facing it mounts the ladder, a climber
    with no input holds with no gravity, and climbing the whole ladder steps
    off ahead onto the top it leads to
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("climbTop")
end
