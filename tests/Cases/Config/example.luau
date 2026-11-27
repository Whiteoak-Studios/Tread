--[[
    The approved example's shared table, server settings and client
    settings, with Frontier Zero's values, pass both entry points' checks
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local served: boolean, serverFailure: any = pcall(Config.server, Example.shared(), Example.server())
	if not served then
		return false, `Config.server refused the approved example: {serverFailure}`
	end

	local started: boolean, clientFailure: any = pcall(Config.client, Example.shared(), Example.client())
	if not started then
		return false, `Config.client refused the approved example: {clientFailure}`
	end

	return true, nil
end
