--[[
    A jump before a mantle adds nothing to its reach: halfway up a jump, a
    top past the reach of the ground last stood on is still refused though
    it lies in reach of the feet, while the same press at a top in reach
    starts the mantle in the air
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("jumpFirst")
end
