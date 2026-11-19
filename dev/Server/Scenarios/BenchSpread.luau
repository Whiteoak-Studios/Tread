--[[
    The relay's two modes over spread players: 149 and then 299 bots, each in
    a cell of its own over a 4,000-stud square, each load run with its bots'
    views in process and then on the relay's workers, one seed each
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local SCENARIOS: { string } = require(ServerScriptService.Server.Bots.Config).spread.scenarios
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).spread.timing
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
