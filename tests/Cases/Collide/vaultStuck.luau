--[[
    A body deeper in the vault than every reach stays where it is, and
    depenetration reports it stuck with how far it sank, here none
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("vaultStuck")
end
