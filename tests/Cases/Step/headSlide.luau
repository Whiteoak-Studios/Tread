--[[
    A body standing on another's head slides off it outward at the game's
    head slide, then drops beside it to the floor
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("headSlide")
end
