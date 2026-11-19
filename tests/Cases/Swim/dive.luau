--[[
    Swimming ahead while looking up rises no higher than the float depth,
    and looking down dives the swimmer until its head is under
--]]

--!strict
local Environment = require("../../Environment")

local SWIMS: string = "tests/Fixtures/Step/Swims.luau"

return function (): (boolean, string | nil)
	return Environment.load(SWIMS).run("dive")
end
