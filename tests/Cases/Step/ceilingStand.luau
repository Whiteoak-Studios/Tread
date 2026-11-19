--[[
    A stand-up under a low ceiling is refused, and walking out the body
    stands only once its standing hull clears the ceiling
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("ceilingStand")
end
