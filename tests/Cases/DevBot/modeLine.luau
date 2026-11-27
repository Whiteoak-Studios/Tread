--[[
    A bot run's mode line names the relay workers the server started,
    whether the load has its views on them, a load that asked for them on a
    server with none running serial, and the views in process and on each
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"

-- Each case: the label, the workers started, what the load asked for, the views in process and on each worker
type Case = { label: string, started: number, asked: boolean?, inProcess: number, views: { number }, line: string }

local CASES: { Case } = {
	{
		label = "Bots S3 seed 1",
		started = 0,
		asked = nil,
		inProcess = 1,
		views = {},
		line = "Bots S3 seed 1 mode: no relay workers started; views 1 in process",
	},
	{
		label = "Bots S3/workers seed 1",
		started = 0,
		asked = true,
		inProcess = 150,
		views = {},
		line = "Bots S3/workers seed 1 mode: no relay workers started, so this load, which asked for them, runs serial; "
			.. "views 150 in process",
	},
	{
		label = "Bots S4/workers seed 1",
		started = 4,
		asked = true,
		inProcess = 1,
		views = { 37, 38, 37, 37 },
		line = "Bots S4/workers seed 1 mode: 4 relay workers started, on for this load; views 1 in process, "
			.. "37/38/37/37 on the workers",
	},
	{
		label = "Bots S4/serial seed 1",
		started = 4,
		asked = false,
		inProcess = 150,
		views = { 0, 0, 0, 0 },
		line = "Bots S4/serial seed 1 mode: 4 relay workers started, off for this load; views 150 in process, "
			.. "0/0/0/0 on the workers",
	},
	{
		label = "Bots S4 seed 1",
		started = 2,
		asked = nil,
		inProcess = 150,
		views = { 0, 0 },
		line = "Bots S4 seed 1 mode: 2 relay workers started, off for this load; views 150 in process, 0/0 on the workers",
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	for _, case: Case in CASES do
		local line: string = Run.modeLine(case.label, case.started, case.asked, case.inProcess, case.views)
		if line ~= case.line then
			return false, `{case.label}'s mode line read:\n{line}\nnot:\n{case.line}`
		end
	end

	return true, nil
end
