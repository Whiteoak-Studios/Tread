--[[
    Under a ceiling that leaves room for the crouched hull and not the
    standing one, a standing body's mantle ends crouched
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("lowCeiling")
end
