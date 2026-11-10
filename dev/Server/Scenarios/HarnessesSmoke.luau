--[[
    Runs G7's and G8's three harnesses briefly, each case firing a short
    while, the G8 load's smoke timing and the first few openings, and passes
    when every one ran cleanly
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)
local Hits = require(ServerScriptService.Server.Hits)
local Reveals = require(ServerScriptService.Server.Reveals)
local Run = require(ServerScriptService.Server.Bots.Run)

local CASES: { Hits.Case } = require(ServerScriptService.Server.Config.Hits).cases
local SECONDS: number = require(ServerScriptService.Server.Config.Hits).smoke
local SMOKE: Config.Timing = require(ServerScriptService.Server.Config.Reveals).smoke
local OPENINGS: number = require(ServerScriptService.Server.Config.Reveals).openings.smoke
local SEPARATOR: string = "; " -- Between the harnesses' lines

return function (): (boolean, string | nil)
	-- Each case as configured, firing only the smoke run's seconds
	local cases: { Hits.Case } = {}
	for _, case: Hits.Case in CASES do
		local short: Hits.Case = table.clone(case)
		short.seconds = SECONDS
		table.insert(cases, short)
	end

	local hits: boolean, hitsLine: string = Hits.run(cases)
	local late: boolean, lateLine: string = Run.run("G8", SMOKE, Reveals.probe())
	local openings: boolean, openingsLine: string = Reveals.openings(OPENINGS)

	return hits and late and openings, table.concat({ hitsLine, lateLine, openingsLine }, SEPARATOR)
end
