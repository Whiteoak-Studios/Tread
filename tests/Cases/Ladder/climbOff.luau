--[[
    A climber looking far enough down climbs down to stand on the ground at
    the ladder's foot, and one moving back along its look backs off the
    ladder and drops to the floor
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("climbOff")
end
