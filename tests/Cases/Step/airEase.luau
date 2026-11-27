--[[
    In the air the level velocity eases toward the move at the game's air
    ease while gravity pulls it down, each tick on its quanta
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("airEase")
end
