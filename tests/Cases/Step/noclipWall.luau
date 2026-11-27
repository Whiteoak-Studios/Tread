--[[
    Noclip flies straight through the wall along the look, with no gravity
    and no ground
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("noclipWall")
end
