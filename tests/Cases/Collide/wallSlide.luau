--[[
    A diagonal walk into the wall stops a skin short of it and slides along
    it the whole way, on Lune's casts over the fixture geometry
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("wallSlide")
end
