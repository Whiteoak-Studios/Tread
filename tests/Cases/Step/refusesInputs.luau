--[[
    The step refuses a move axis past 1, any input that is not finite and a
    command with no presses, before it changes the state
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("refusesInputs")
end
