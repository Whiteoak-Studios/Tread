--[[
    The step refuses a rules function that returns anything but a speed cap
    of 0 or more
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("refusesRules")
end
