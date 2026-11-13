--[[
    A swimmer's reach counts from its feet, so it climbs out of the pool onto
    an edge past the reach of the pool floor it last stood on, and ends
    standing there out of the water
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("swimmerOut")
end
