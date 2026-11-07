--[[
    A move input longer than 1 gains nothing: its diagonal ends where one
    scaled to a length of 1 ends, at the walk speed
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("longMove")
end
