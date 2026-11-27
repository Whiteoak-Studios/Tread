--[[
    An idle swimmer floats at the game's float depth with its head above the
    water, rising to it from under it and sinking to it from over it, and
    stays there
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("float")
end
