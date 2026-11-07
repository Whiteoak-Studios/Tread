--[[
    Parked holds a body still where it is, in the air too, whatever its
    command asks
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("parked")
end
