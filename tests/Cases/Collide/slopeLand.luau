--[[
    Landing on the 55° slope, steep but still stood on, grounds the body with
    its uphill edge a skin from the face
--]]

--!strict
local Environment = require("../../Environment")

local WALKS: string = "tests/Fixtures/Step/Walks.luau"

return function (): (boolean, string | nil)
	return Environment.load(WALKS).run("slopeLand")
end
