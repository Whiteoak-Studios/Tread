--[[
    The live runs' trigger on the dev server: a player's ask over the dev
    scope runs a scenario through the Runner, and the run's Output goes
    back to that player as a report in pieces, then its verdict
--]]

--!strict
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local LiveRuns = require(ReplicatedStorage.Shared.Dev.LiveRuns)
local Runner = require(ServerScriptService.Server.Runner)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Live).rate
local PIECE_BYTES: number = require(ServerScriptService.Server.Config.Live).pieceBytes
local REPORT_BYTES: number = require(ServerScriptService.Server.Config.Live).reportBytes
local VERDICT_WAIT: number = require(ServerScriptService.Server.Config.Live).verdictWait
local DROPPED: { string } = require(ServerScriptService.Server.Config.Live).dropped

-- What a line of each kind but plain output carries in front of it in the report
local PREFIXES: { [Enum.MessageType]: string } = {
	[Enum.MessageType.MessageWarning] = "Warning",
	[Enum.MessageType.MessageError] = "Error",
}

type Key = Player | Volt.Bot

local Running: string? = nil -- The run going, beside which no other starts
local Started: boolean = false

local Live = {}

-- A line of Output as the report shows it, a warning or an error with its kind in front
local function lineOf(message: string, kind: Enum.MessageType): string
	local prefix: string? = PREFIXES[kind]
	if prefix then
		return `{prefix}: {message}`
	end

	return message
end

--[[
    One run for the player who asked: the Runner runs it while its Output
    is collected, until the Runner's verdict line arrives or the wait for
    it passes its deadline, then the report goes to them in pieces, one a
    frame, and the verdict after, each only while they are still in
--]]

local function report(player: Player, name: string, collected: LiveRuns.Report, output: RBXScriptConnection)
	Network.runReport.fire(player, "Running", name)
	local passed: boolean = Runner.run(name)

	-- The listener hears the run's last lines frames after the run returns, so it stays connected, checked each frame,
	-- until the verdict line arrives or the deadline passes, when the report says the line never came
	local deadline: number = os.clock() + VERDICT_WAIT
	while not collected.heard and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	output:Disconnect()
	LiveRuns.close(collected, VERDICT_WAIT)

	for _, piece: string in LiveRuns.split(LiveRuns.text(collected), PIECE_BYTES) do
		if player.Parent == nil then
			return
		end

		Network.runReport.fire(player, "Piece", piece)
		RunService.Heartbeat:Wait()
	end

	if player.Parent ~= nil then
		local verdict: LiveRuns.State = passed and "Passed" or "Failed"
		Network.runReport.fire(player, verdict, name)
	end
end

--[[
    Starts the run a player asked for, unless the server refuses it, when
    the player is told why. Whatever the run does, its Output listener is
    disconnected, and only then may the next run start
--]]

local function begin(key: Key, name: string)
	local refusal: string? = LiveRuns.refusal(Running, name)
	if refusal then
		Network.runReport.fire(key, "Refused", refusal)
		return
	end

	-- A Volt bot fires none of the dev scope's events, so whoever asked is a player
	local player: Player = key :: Player
	Running = name

	local collected: LiveRuns.Report = LiveRuns.report(name, REPORT_BYTES, DROPPED)
	local output: RBXScriptConnection = LogService.MessageOut:Connect(function (message: string, kind: Enum.MessageType)
		LiveRuns.collect(collected, lineOf(message, kind))
	end)

	local ran: boolean, failure: any = pcall(report, player, name, collected, output)
	output:Disconnect()
	Running = nil

	if not ran then
		warn(`The live run {name} for {player.Name} stopped before its report was sent: {failure}`)
	end
end

--[[
    Binds the run event at the dev game's own rate, each ask on a thread
    of its own. It runs once a server, and its listener lives as long as
    the server
--]]

function Live.start()
	if Started then
		error("Live.start runs once a server, and it has already run", 2)
	end

	Started = true
	Network.rate("run", RATE.perSecond, RATE.burst)
	Network.run.on(function (key: Key, name: string)
		task.spawn(begin, key, name)
	end)
end

return Live
