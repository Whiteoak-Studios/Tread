--[[
    Depenetration's exact query finds a body inside the wall and moves it to
    the first clear spot in the fixed order, a hull's width along +X
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("wallInside")
end
