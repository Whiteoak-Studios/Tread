--[[
    A walk ahead turned a quarter turn goes along -X, through the step's own
    sine and cosine of the yaw, and faces that way
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("turnedWalk")
end
