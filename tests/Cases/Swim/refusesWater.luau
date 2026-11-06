--[[
    A water query that gives anything but a finite height or nil is
    refused, naming what it gave
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("refusesWater")
end
