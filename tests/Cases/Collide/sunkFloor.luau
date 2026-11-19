--[[
    Depenetration finds a body sunk into the floor by the rest height alone
    and lifts it by its sinking to rest a skin above
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("sunkFloor")
end
