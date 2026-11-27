--[[
    In open air the cleared eye is the wanted eye: the eased height, moved
    by the lean's share of the game's shift along the body's own axes
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("eyeOpen")
end
