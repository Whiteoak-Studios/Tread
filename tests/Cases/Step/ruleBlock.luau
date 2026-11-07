--[[
    The rules function's writes to its rule-state block are kept from step to
    step and carried by a copy, and it is told when it steps an NPC
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("ruleBlock")
end
