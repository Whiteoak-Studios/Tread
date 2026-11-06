--[[
    Crouching and standing keep the feet in place while the eye eases to
    each posture's height and gets there
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("crouchStand")
end
