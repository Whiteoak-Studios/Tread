--[[
    A head offset past the game's cone is clamped to it in the command, and
    lean is zeroed while the offset is set and comes back once it is not
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("headCone")
end
