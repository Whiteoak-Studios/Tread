--[[
    Tread's arm of the versus run against default Humanoids: S3's city mix
    and S4's fight at 150 and at 300 players, one short seed each, with
    every real player's receive rates beside each window
--]]

--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ClientLines = require(ServerScriptService.Server.Bots.ClientLines)
local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)

local SCENARIOS: { string } = require(ServerScriptService.Server.Bots.Config).versus.scenarios
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).versus.timing
local ATTRIBUTE: string = require(ServerScriptService.Server.Config.Versus).attribute
local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Versus).rate
local WAIT: number = require(ServerScriptService.Server.Config.Versus).wait
local SEPARATOR: string = "; " -- Between the parts of one line

-- Runs each load in turn with the probe beside its window, giving whether every one drove and cleaned up, a line each
local function runAll(probe: Run.Probe): (boolean, string)
	local passed: boolean = true
	local lines: { string } = {}

	for _, name: string in SCENARIOS do
		local ok: boolean, line: string = Run.run(name, TIMING, probe, nil)
		passed = passed and ok
		table.insert(lines, line)
	end

	return passed, table.concat(lines, SEPARATOR)
end

return function (): (boolean, string | nil)
	if #Players:GetPlayers() == 0 then
		return false, "no real player is in to measure the receive rates on"
	end

	local window: ClientLines.Window = ClientLines.new(ATTRIBUTE, WAIT)
	local stop: () -> () = ClientLines.listen(window, RATE)
	local probe: Run.Probe = ClientLines.probe(window, nil)
	local ran: boolean, passed: any, line: any = pcall(runAll, probe)

	-- Everything it set goes, whatever the run did
	stop()

	if not ran then
		return false, `it threw: {passed}`
	elseif #window.problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(window.problems, SEPARATOR)}`
	end

	return passed, line
end
