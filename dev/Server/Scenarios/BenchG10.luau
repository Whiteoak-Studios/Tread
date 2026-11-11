--[[
    Benchmark G10 at 300 players: 299 bots spread over the map with 32
    awake NPCs, then the ladder's rung that idles every NPC, each run for
    each seed with Tread's stats printed each second and no pass line
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local FULL: Config.Timing = require(ServerScriptService.Server.Bots.Config).full
local RUNGS: { string } = { "G10", "G10Rung2" } -- The load, then the ladder's rungs this place runs, in turn
local CLOSING: string = "Bots G10: the ladder's Actor and validate-only rungs run on branches of their own, not here"
local SEPARATOR: string = "; " -- Between the rungs' lines

return function (): (boolean, string | nil)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in RUNGS do
		local ok: boolean, line: string = Run.run(name, FULL)
		passed = passed and ok
		table.insert(lines, line)
	end

	print(CLOSING)
	table.insert(lines, CLOSING)

	return passed, table.concat(lines, SEPARATOR)
end
