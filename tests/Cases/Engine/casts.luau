--[[
    The casts the step reads give the distances and normals the fixture's faces
    should, the questions the live scenario puts to Engine.collision too
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("casts")
end
