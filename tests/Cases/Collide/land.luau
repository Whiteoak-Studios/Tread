--[[
    A falling body lands on the floor through the ground probe, a skin above
    it, on the ground with its fall stopped
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("land")
end
