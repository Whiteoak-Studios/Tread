--[[
    The relevancy sweep: S3's city mix and S4's fight each run at every
    render distance in turn, every viewer set to it, bots and real players
    alike, each run opening with the server's speed calibration
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local SCENARIOS: { string } = require(ServerScriptService.Server.Bots.Config).relevancy.scenarios
local DISTANCES: { number } = require(ServerScriptService.Server.Bots.Config).relevancy.distances
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).relevancy.timing
local SEPARATOR: string = "; " -- Between the runs' lines

return function (): (boolean, string | nil)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in SCENARIOS do
		for _, distance: number in DISTANCES do
			local ok: boolean, line: string = Run.run(name, TIMING, nil, distance)
			passed = passed and ok
			table.insert(lines, line)
		end
	end

	return passed, table.concat(lines, SEPARATOR)
end
