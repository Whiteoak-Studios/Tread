--[[
    A fall from 10 studs counts a landing, heavy, at a speed past any a jump
    on level ground lands at
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("fallHeavy")
end
