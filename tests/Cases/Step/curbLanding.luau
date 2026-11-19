--[[
    A half-stud drop lands inside the game's landing airtime, so the body is
    grounded with no landing counted and no landing speed handed back
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("curbLanding")
end
