--[[
    Runs each of the bot harness's scenarios S0 to S7 once, briefly, and
    passes when every one drove its bots and took away all it made
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local ORDER: { string } = require(ServerScriptService.Server.Bots.Config).order
local SMOKE: Config.Timing = require(ServerScriptService.Server.Bots.Config).smoke
local SEPARATOR: string = "; " -- Between the scenarios' lines

return function (): (boolean, string | nil)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in ORDER do
		local ok: boolean, line: string = Run.run(name, SMOKE)
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end
