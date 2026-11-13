--[[
    A rules function's allow.jump gives a jump just after leaving the ground,
    coyote time, and none once that time has passed
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("coyoteJump")
end
