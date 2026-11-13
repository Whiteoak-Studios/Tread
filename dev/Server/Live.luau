--[[
    The live runs' trigger on the dev server: a player's ask runs a scenario
    or the Run all queue through the Runner, each run's Output its report,
    sent in pieces, and the queue's reports kept, saved and listed too
--]]

--!strict
local DataStoreService = game:GetService("DataStoreService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local BotPanel = require(ServerScriptService.Server.BotPanel)
local Calibration = require(ServerScriptService.Server.Calibration)
local LiveRuns = require(ReplicatedStorage.Shared.Dev.LiveRuns)
local Runner = require(ServerScriptService.Server.Runner)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Live).rate
local PIECE_BYTES: number = require(ServerScriptService.Server.Config.Live).pieceBytes
local REPORT_BYTES: number = require(ServerScriptService.Server.Config.Live).reportBytes
local VERDICT_WAIT: number = require(ServerScriptService.Server.Config.Live).verdictWait
local DROPPED: { string } = require(ServerScriptService.Server.Config.Live).dropped
local STORE: string = require(ServerScriptService.Server.Config.Live).queue.store
local TRIES: number = require(ServerScriptService.Server.Config.Live).queue.tries
local RETRY_WAIT: number = require(ServerScriptService.Server.Config.Live).queue.retryWait
local CALIBRATION: string = "Calibration" -- What the queue's list calls the calibration it opens with
local NEWLINE: string = "\n" -- Between the kept list's lines

-- What a line of each kind but plain output carries in front of it in the report
local PREFIXES: { [Enum.MessageType]: string } = {
	[Enum.MessageType.MessageWarning] = "Warning",
	[Enum.MessageType.MessageError] = "Error",
}

type Key = Player | Volt.Bot

-- One report the Run all queue kept, which the server holds until the next queue starts
type Kept = {
	name: string,
	passed: boolean,
	text: string,
	saved: boolean, -- Whether the experience's DataStore took it
}

local Running: string? = nil -- The run going, beside which no other starts, the queue's own while it runs
local Started: boolean = false
local Queue: { Kept } = {} -- The latest queue's reports, in the order kept
local QueueLine: string = "" -- The latest queue's status line, empty before any

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
    Runs one scenario through the Runner while its Output is collected,
    until the Runner's verdict line arrives or the wait for it passes its
    deadline, and gives whether it passed and its report's text
--]]

local function collect(name: string): (boolean, string)
	local collected: LiveRuns.Report = LiveRuns.report(name, REPORT_BYTES, DROPPED)
	local output: RBXScriptConnection = LogService.MessageOut:Connect(function (message: string, kind: Enum.MessageType)
		LiveRuns.collect(collected, lineOf(message, kind))
	end)

	-- The listener hears the run's last lines frames after the run returns, so it stays connected, checked each frame,
	-- until the verdict line arrives or the deadline passes, and goes whatever happened
	local ran: boolean, passed: any = pcall(function (): boolean
		local verdict: boolean = Runner.run(name)
		local deadline: number = os.clock() + VERDICT_WAIT

		while not collected.heard and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end

		return verdict
	end)

	output:Disconnect()
	LiveRuns.close(collected, VERDICT_WAIT)

	if not ran then
		LiveRuns.collect(collected, `The live run of {name} stopped: {passed}`)
	end

	return ran and passed == true, LiveRuns.text(collected)
end

-- Sends a report's text in pieces, one a frame, each only while the player is still in, and gives whether they stayed
local function pieces(player: Player, text: string): boolean
	for _, piece: string in LiveRuns.split(text, PIECE_BYTES) do
		if player.Parent == nil then
			return false
		end

		Network.runReport.fire(player, "Piece", piece)
		RunService.Heartbeat:Wait()
	end

	return player.Parent ~= nil
end

-- One run for the player who asked: running as it starts, then its report in pieces and its verdict
local function single(player: Player, name: string)
	Network.runReport.fire(player, "Running", name)

	local passed: boolean, text: string = collect(name)
	if pieces(player, text) then
		local verdict: LiveRuns.State = passed and "Passed" or "Failed"
		Network.runReport.fire(player, verdict, name)
	end
end

-- A kept report's line in the queue's list, by its place
local function label(index: number, kept: Kept): string
	local verdict: string = kept.passed and "passed" or "failed"
	local unsaved: string = kept.saved and "" or ", not saved"

	return `{index}. {kept.name} {verdict}{unsaved}`
end

-- The queue's status line and its list of kept reports, a line each, to one player
local function tell(player: Player)
	local lines: { string } = {}
	for index: number, kept: Kept in Queue do
		table.insert(lines, label(index, kept))
	end

	Network.runReport.fire(player, "Queue", QueueLine)
	Network.runReport.fire(player, "Kept", table.concat(lines, NEWLINE))
end

local function tellAll()
	for _, player: Player in Players:GetPlayers() do
		tell(player)
	end
end

--[[
    Writes one key of the queue's DataStore, each try under its own pcall,
    up to TRIES tries a wait apart, and gives the last try's failure, nil
    once one took
--]]

local function save(store: DataStore, key: string, value: any): string?
	local failure: any = nil

	for try: number = 1, TRIES do
		local saved: boolean, problem: any = pcall(function ()
			store:SetAsync(key, value)
		end)
		if saved then
			return nil
		end

		failure = problem
		if try < TRIES then
			task.wait(RETRY_WAIT)
		end
	end

	return tostring(failure)
end

--[[
    Keeps one of the queue's reports on the server, saves it under the
    queue's start and its place with the start's index key listing every
    report so far, warns of a write that failed, then tells every player
--]]

local function record(store: DataStore?, started: number, name: string, passed: boolean, text: string)
	local index: number = #Queue + 1
	local kept: Kept = { name = name, passed = passed, text = text, saved = false }
	table.insert(Queue, kept)

	local failure: string? = "the experience's DataStore did not open"
	if store then
		failure = save(store, `{started}-{index}`, text)
	end

	if store and not failure then
		local listed: { { name: string, passed: boolean } } = {}
		for _, each: Kept in Queue do
			table.insert(listed, { name = each.name, passed = each.passed })
		end

		failure = save(store, `{started}`, listed)
	end

	kept.saved = failure == nil
	if failure then
		warn(`Run all kept {name}'s report on the server, and its save under {started}-{index} failed: {failure}`)
	end

	tellAll()
end

--[[
    The Run all queue on a fresh kept list: the calibration kept first, then
    each queued run in turn, every report kept and saved whatever its run
    did, the status line told to every player as each starts and at the end
--]]

local function runAll()
	local started: number = os.time()
	local store: DataStore? = nil
	local opened: boolean, result: any = pcall(function (): DataStore
		return DataStoreService:GetDataStore(STORE)
	end)
	if opened then
		store = result
	else
		warn(`Run all saves nothing, since the experience's DataStore {STORE} did not open: {result}`)
	end

	table.clear(Queue)

	local function status(going: string?, left: number)
		local failed: number = 0
		for _, kept: Kept in Queue do
			if not kept.passed then
				failed += 1
			end
		end

		QueueLine = LiveRuns.queueStatus(going, left, #Queue, failed)
		tellAll()
	end

	status(CALIBRATION, #LiveRuns.queue)

	local calibrated: boolean, line: string = Calibration.run()
	record(store, started, CALIBRATION, calibrated, `Run all {started} calibration: {line}`)

	Live.drain(LiveRuns.queue, function (name: string, left: number): (boolean, string)
		Running = name
		status(name, left)

		return collect(name)
	end, function (name: string, passed: boolean, text: string)
		record(store, started, name, passed, text)
	end)

	status(nil, 0)
end

-- A player's ask for the queue's kept reports: one by its place, its line then its pieces, or the status and list
local function show(player: Player, index: number)
	local kept: Kept? = Queue[index]
	if not kept then
		return tell(player)
	end

	Network.runReport.fire(player, "Report", label(index, kept))
	pieces(player, kept.text)
end

--[[
    Starts what a player asked for, unless the server refuses it, when the
    player is told why: a run going, the queue's included, a name not listed,
    or the bot panel's bots on the server, which the run's own bots would
    meet. An ask for a kept report is never refused. Only once the run or
    the queue ends may the next start
--]]

local function begin(key: Key, name: string)
	-- A Volt bot fires none of the dev scope's events, so whoever asked is a player
	local player: Player = key :: Player
	local index: number? = LiveRuns.keptIndex(name)
	if index then
		return show(player, index)
	end

	local refusal: string? = LiveRuns.refusal(Running, name)
	if not refusal and BotPanel.holds() then
		refusal = "the bot panel's bots are on the server, so clear the panel's bots first"
	end

	if refusal then
		Network.runReport.fire(key, "Refused", refusal)
		return
	end

	Running = name

	local ran: boolean, failure: any = false, nil
	if name == LiveRuns.ALL then
		ran, failure = pcall(runAll)
	else
		ran, failure = pcall(single, player, name)
	end

	Running = nil

	if not ran then
		warn(`The live run {name} for {player.Name} stopped before its report was sent: {failure}`)
	end
end

--[[
    Runs each name in turn through run, which is told how many follow it,
    and hands each one's report to keep, a run that fails or throws kept as
    failed and the next started all the same
--]]

function Live.drain(
	names: { string },
	run: (name: string, left: number) -> (boolean, string),
	keep: (name: string, passed: boolean, text: string) -> ()
)
	for index: number, name: string in names do
		local ran: boolean, passed: any, text: any = pcall(run, name, #names - index)
		if not ran then
			text = `{name}: its run threw: {passed}`
			passed = false
		end

		local kept: boolean, failure: any = pcall(keep, name, passed == true, tostring(text))
		if not kept then
			warn(`Run all could not keep {name}'s report, and went on: {failure}`)
		end
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

-- The run going, nil while none is, beside which the bot panel spawns nothing
function Live.running(): string?
	return Running
end

return Live
