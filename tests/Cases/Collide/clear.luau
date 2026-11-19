--[[
    Collide.clear: a hull in open air and one a quantum above the floor are
    clear, one in the wall and one a quantum into the floor are not
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("clear")
end
