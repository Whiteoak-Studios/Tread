--[[
    The bot panel's split line: the loop's state, the share of the read's
    ticks that deferred, one a Heartbeat flagged DEFERRED, the history's
    send term in milliseconds, and the views in process and on each worker
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Server/BotPanel.luau"
local RUN: string = "dev/Server/Bots/Run.luau"
local SEND_LAG: number = 0.0334 -- Seconds, a stand-in for the history's send term
local TICKS: number = 5 -- The read's ticks
local VIEWS: { number } = { 25, 25, 25, 24 } -- Each worker's views, a 99-bot spawn on 4 workers

-- One line's inputs and the line they give
type Line = {
	on: boolean,
	flags: { number },
	ticks: number,
	sendLag: number,
	inProcess: number,
	views: { number },
	text: string,
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local Tick: any = loaded.require(dataModel:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	-- Stand-ins for the dev game, its fleet and the dev scope, whose real modules start the dev game's server
	local files: { [any]: string } = { [server.BotPanel] = BOT_PANEL, [server.Bots.Run] = RUN }
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {}, [shared.Network.Server] = {} }
	local BotPanel: any = Kit.loader(dataModel, files, results, loaded.require)(server.BotPanel)

	local ticked: number, held: number, polled: number = Tick.TICKED, Tick.HELD, Tick.POLLED
	local released: number, deferred: number = Tick.RELEASED, Tick.DEFERRED

	-- A spread tick, a serial one held and released, a spread one released late, and a skipped rest: 3 Heartbeats
	-- flagged DEFERRED of the 5 ticks, a 60% share
	local window: { number } = {
		ticked,
		deferred + held,
		polled + released,
		ticked + held,
		polled + released,
		ticked,
		deferred + held,
		polled + held,
		polled + released,
		ticked,
		deferred + ticked + held,
		polled + released,
	}

	local lines: { Line } = {
		{
			on = true,
			flags = window,
			ticks = TICKS,
			sendLag = SEND_LAG,
			inProcess = 1,
			views = VIEWS,
			text = "Split on: 3 of 5 ticks deferred, 60.0%; send term 33.400 ms; views 1 in process, 25/25/25/24 on the workers",
		},
		{
			-- Off on a server with no relay workers, no Heartbeat deferred and no term
			on = false,
			flags = { ticked + held, polled + released, ticked, 0 },
			ticks = 20,
			sendLag = 0,
			inProcess = 1,
			views = {},
			text = "Split off: 0 of 20 ticks deferred, 0.0%; send term 0.000 ms; views 1 in process",
		},
		{
			-- A read with no tick, as while the loop stalls, gives no share past 0
			on = true,
			flags = {},
			ticks = 0,
			sendLag = SEND_LAG,
			inProcess = 0,
			views = { 0, 0 },
			text = "Split on: 0 of 0 ticks deferred, 0.0%; send term 33.400 ms; views 0 in process, 0/0 on the workers",
		},
	}

	for index: number, line: Line in lines do
		local got: string =
			BotPanel.splitLine(line.on, line.flags, line.ticks, line.sendLag, line.inProcess, line.views)
		if got ~= line.text then
			return false, `Line {index} read "{got}", not "{line.text}"`
		end
	end

	return true, nil
end
