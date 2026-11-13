--[[
    A body inside the wall leaves it on the tenth command's exact overlap
    check and not before, and one no spot frees is handed back stuck
--]]

--!strict
local Environment = require("../../Environment")

local TICKS: string = "tests/Fixtures/Step/Ticks.luau"

return function (): (boolean, string | nil)
	return Environment.load(TICKS).run("tenthCommand")
end
