--[[
    A jump press starts no mantle at a wall past the reach, at a ledge the
    walk steps onto, under a ceiling with room for no hull, facing away from
    the ledge, or downed, and jumps instead
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("refuses")
end
