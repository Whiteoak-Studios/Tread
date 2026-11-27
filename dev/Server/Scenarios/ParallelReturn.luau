--[[
    When results sent from a Heartbeat come back from Actors, what crosses
    between VMs and as what, and what sends and returns of each size cost,
    a line each result with nothing judged and no bots loading the server
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Returns = require(ServerScriptService.Server.Parallel.Returns)

local PREFIX: string = "ParallelReturn" -- What each of the scenario's lines begins with
local SEPARATOR: string = "; " -- Between the problems

-- Each probe takes its own clones and gives its lines and why it stopped short, P1, P4 and P5 in turn
local PROBES: { () -> ({ string }, { string }) } = { Returns.timing, Returns.crossing, Returns.sizes }

return function (): (boolean, string | nil)
	local problems: { string } = {}

	for _, probe: () -> ({ string }, { string }) in PROBES do
		local lines: { string }, stopped: { string } = probe()

		for _, line: string in lines do
			print(`{PREFIX} {line}`)
		end

		for _, problem: string in stopped do
			table.insert(problems, problem)
		end
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
