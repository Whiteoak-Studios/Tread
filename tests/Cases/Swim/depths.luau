--[[
    Swimming starts in water just over the game's enter depth, keeping its
    entry share of the velocity, and not just under it, and ends in water
    just under the leave depth and not just over it
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("depths")
end
