--[[
    The relay's two modes on one server: S3's city mix and S4's fight, each
    run with its bots' views in process and then on the relay's workers,
    back to back, one seed each, every half with its own window and lines
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local SCENARIOS: { string } = require(ServerScriptService.Server.Bots.Config).workers.scenarios
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).workers.timing
local MODES: { boolean } = { false, true } -- In process first, then on the workers
local SEPARATOR: string = "; " -- Between the halves' lines

return function (): (boolean, string | nil)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in SCENARIOS do
		for _, workers: boolean in MODES do
			local ok: boolean, line: string = Run.runWorkers(name, TIMING, workers, nil)
			passed = passed and ok
			table.insert(lines, line)
		end
	end

	return passed, table.concat(lines, SEPARATOR)
end
