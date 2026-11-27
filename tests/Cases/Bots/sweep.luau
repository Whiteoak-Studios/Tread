--[[
    The relevancy sweep runs each of its config's scenarios at each of its
    config's render distances in that order, with the config's timing, and
    goes on past a run that fails, failing the sweep
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SWEEP: string = "dev/Server/Scenarios/BenchRelevancy.luau"
local FAILING: string = "S3@222" -- The stand-in run that fails

-- A config of the sweep's own, so every name and distance the sweep runs can only have come from it
local TIMING: { [string]: any } = { seeds = { 7 }, warmup = 1, window = 2, interval = 1 }
local CONFIG: { [string]: any } = {
	relevancy = { scenarios = { "S3", "S4" }, distances = { 111, 222, 333 }, timing = TIMING },
}

local EXPECTED: string = "S3@111,S3@222,S3@333,S4@111,S4@222,S4@333"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local calls: { string } = {}
	local timings: number = 0

	local run: any = {
		run = function (name: string, timing: any, probe: any, distance: number): (boolean, string)
			local called: string = `{name}@{distance}`
			table.insert(calls, called)

			if timing == TIMING and probe == nil then
				timings += 1
			end

			return called ~= FAILING, called
		end,
	}

	local files: { [any]: string } = { [server.Scenarios.BenchRelevancy] = SWEEP }
	local results: { [any]: any } = { [server.Bots.Run] = run, [server.Bots.Config] = CONFIG }
	local sweep: any = Kit.loader(loaded.game, files, results, loaded.require)(server.Scenarios.BenchRelevancy)

	local passed: boolean, line: string = sweep()
	if table.concat(calls, ",") ~= EXPECTED then
		return false, `The sweep ran {table.concat(calls, ",")}, not {EXPECTED}`
	elseif timings ~= #calls then
		return false, `{#calls - timings} of the sweep's runs took another timing than its config's, or a probe`
	elseif passed then
		return false, `The sweep passed with {FAILING} failing`
	elseif line ~= table.concat(calls, "; ") then
		return false, `The sweep's report read {line}`
	end

	return true, nil
end
