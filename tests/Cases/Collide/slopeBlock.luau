--[[
    Walking into a 55° slope, steeper than walkable, gains no height and stops
    with the hull's front edge a skin from the face
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("slopeBlock")
end
