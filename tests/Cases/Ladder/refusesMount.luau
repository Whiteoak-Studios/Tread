--[[
    No ladder is mounted by a body backing into its box, one facing away
    from it, or one downed
--]]

--!strict
local Environment = require("../../Environment")

local LADDERS: string = "tests/Fixtures/Step/Ladders.luau"

return function (): (boolean, string | nil)
	return Environment.load(LADDERS).run("refusesMount")
end
