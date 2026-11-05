--[[
    Walking off the riser's 1-stud edge, past the snap's reach, the body
    leaves the ground where the edge left it
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("dropOff")
end
