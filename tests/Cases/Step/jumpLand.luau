--[[
    One jump press leaves the ground, counts one jump, tracks its apex, and
    lands back on the floor once, light
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("jumpLand")
end
