--[[
    The step refuses a mode or a move mode it has no tick for, naming it
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("refusesModes")
end
