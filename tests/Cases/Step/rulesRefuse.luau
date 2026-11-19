--[[
    The rules function's refusals hold: no jump, no sprint and no crouch on
    a press of each, and a crouched body it refuses a stand stays crouched
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("rulesRefuse")
end
