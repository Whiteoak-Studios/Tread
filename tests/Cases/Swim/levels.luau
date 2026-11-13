--[[
    The water level a state carries for its state word is dry out of the
    water, wading on a shelf, at the surface floating and under while the
    eye is below the surface
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("levels")
end
