--[[
    A fall that ends in deep water counts its landing with water as the
    material, and keeps the game's entry share of the fall
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("waterLanding")
end
