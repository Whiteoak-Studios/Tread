--[[
    A grounded walk ahead at yaw 0 moves along -Z at the walk speed, set at
    once, and stays on the ground the whole way
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("walkForward")
end
