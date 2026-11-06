--[[
    Feet deeper in water than the game's crouch depth refuse a crouch and
    stand a crouched wader up, while feet shallower than it crouch
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("crouchDepth")
end
