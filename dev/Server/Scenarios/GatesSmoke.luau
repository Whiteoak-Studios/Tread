--[[
    Runs each of the gates' loads once, briefly, and passes when every one
    built its bodies, drove them and took away all it made
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local GATES: { string } = require(ServerScriptService.Server.Bots.Config).gates
local SMOKE: Config.Timing = require(ServerScriptService.Server.Bots.Config).smoke
local SEPARATOR: string = "; " -- Between the loads' lines

return function (): (boolean, string | nil)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in GATES do
		local ok: boolean, line: string = Run.run(name, SMOKE)
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end
