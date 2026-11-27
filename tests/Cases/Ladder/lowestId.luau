--[[
    A body touching two ladders at once climbs the one with the lower id,
    which its state names
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("lowestId")
end
