--[[
    Another body standing on the top blocks a mantle's path, which drops
    into the air where it stopped beside the face, and the body falls back
    to the floor
--]]

--!strict
local Environment = require("../../Environment")

local MANTLES: string = "tests/Fixtures/Step/Mantles.luau"

return function (): (boolean, string | nil)
	return Environment.load(MANTLES).run("blocked")
end
