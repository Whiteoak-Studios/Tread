--[[
    A lean past the game's limit stops at it, moving at most the lean rate a
    tick, either way, on the lean's i8 steps
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("lean")
end
