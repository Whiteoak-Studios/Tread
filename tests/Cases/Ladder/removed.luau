--[[
    A ladder taken out while it is climbed drops the climber into the air,
    and it falls to the floor
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("removed")
end
