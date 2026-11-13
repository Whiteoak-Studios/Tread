--[[
    Run all's queue holds the benchmarks in their order, each a listed run,
    and the server runs it through a stand-in runner in that order, keeping
    a failed run's report and a thrown one's as failed and going on past both
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local LIVE: string = "dev/Server/Live.luau"
local FAILING: string = "BenchS3" -- The stand-in run that returns false
local THROWING: string = "BenchS9" -- The one that throws

local ORDER: { string } = {
	"BenchS0",
	"BenchS1",
	"BenchS2",
	"BenchS3",
	"BenchS4",
	"BenchS5",
	"BenchS6",
	"BenchS7",
	"BenchS3Npcs",
	"BenchS4Npcs",
	"BenchS9",
	"BenchS10",
	"BenchRelevancy",
	"BenchG10",
	"BenchG10Rung2",
	"LateReveals",
	"Openings",
	"ClientCost",
	"ParallelProbe",
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)

	-- 1) The queue's order, each a run the panel lists
	if table.concat(LiveRuns.queue, ",") ~= table.concat(ORDER, ",") then
		return false, `The queue runs {table.concat(LiveRuns.queue, ",")}`
	end

	local listed: { [string]: boolean } = {}
	for _, run: any in LiveRuns.runs do
		listed[run.name] = true
	end

	for _, name: string in LiveRuns.queue do
		if not listed[name] then
			return false, `The queue runs {name}, which the panel doesn't list`
		end
	end

	-- 2) The server's queue over a stand-in runner, its dev scope, bot panel and Runner standing in too
	local results: { [any]: any } = {
		[shared.Network.Server] = {},
		[server.BotPanel] = {},
		[server.Runner] = {},
	}

	local Live: any = Kit.loader(dataModel, { [server.Live] = LIVE }, results, loaded.require)(server.Live)
	local ran: { string } = {}
	local kept: { string } = {}

	Live.drain(LiveRuns.queue, function (name: string, left: number): (boolean, string)
		table.insert(ran, `{name} {left}`)
		if name == THROWING then
			error("a stand-in throw", 0)
		end

		return name ~= FAILING, `{name}'s report`
	end, function (name: string, passed: boolean, text: string)
		table.insert(kept, `{name} {passed} {text}`)
	end)

	for index: number, name: string in ORDER do
		local left: number = #ORDER - index
		local passed: boolean = name ~= FAILING and name ~= THROWING
		local text: string = `{name}'s report`
		if name == THROWING then
			text = `{name}: its run threw: a stand-in throw`
		end

		if ran[index] ~= `{name} {left}` then
			return false, `Run {index} of the queue was {ran[index]}, not {name} with {left} left`
		elseif kept[index] ~= `{name} {passed} {text}` then
			return false, `Report {index} of the queue was kept as {kept[index]}`
		end
	end

	if #ran ~= #ORDER or #kept ~= #ORDER then
		return false, `The queue ran {#ran} and kept {#kept} of its {#ORDER}`
	end

	return true, nil
end
