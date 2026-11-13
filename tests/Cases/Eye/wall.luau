--[[
    Pressed to the wall and leaning into it, the cleared eye holds the
    game's clearance from the wall's face, behind the head's center
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("eyeWall")
end
