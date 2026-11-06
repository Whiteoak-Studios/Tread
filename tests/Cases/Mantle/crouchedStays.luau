--[[
    A body crouched when its mantle starts is crouched when it ends, though
    the top it ends on has room to stand
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("crouchedStays")
end
