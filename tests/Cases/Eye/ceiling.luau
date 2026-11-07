--[[
    Crouched under a low ceiling, the cleared eye holds the game's clearance
    below its underside
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("eyeCeiling")
end
