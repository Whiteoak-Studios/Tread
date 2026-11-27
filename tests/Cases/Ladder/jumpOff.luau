--[[
    A jump press on a ladder launches the climber off along its look at the
    game's ladder jump, and counts as a jump
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("jumpOff")
end
