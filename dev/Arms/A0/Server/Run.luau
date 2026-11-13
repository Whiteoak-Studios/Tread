--[[
    Measures one run on an arm's server: starts its load, waits out the
    warm-up, samples the steady window and records the run's report line
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Arm.Config)
local Report = require(ReplicatedStorage.Arm.Report)

local RUN_ATTRIBUTE: string = Config.runAttribute
local STEADY_ATTRIBUTE: string = Config.steadyAttribute
local REPORT_NAME: string = Config.reportName
local WARMUP_SECONDS: number = Config.warmupSeconds
local STEADY_SECONDS: number = Config.steadySeconds
local SAMPLE_INTERVAL: number = Config.sampleInterval
local PERCENTILES: { number } = Config.percentiles
local FPS_PERCENTILE: number = Config.fpsPercentile
local MS_PER_SECOND: number = 1000
local SEPARATOR: string = "; " -- Between the figures of one report line

local Types = require(ReplicatedStorage.Arm.Types)

type Load = Types.Load

local Run = {}

--[[
    The server's report, a StringValue in ServerStorage that holds a line
    per run and per settings check, made the first time a line is recorded
--]]

local function reportValue(): StringValue
	local report = ServerStorage:FindFirstChild(REPORT_NAME) :: StringValue?
	if report then
		return report
	end

	local created: StringValue = Instance.new("StringValue")
	created.Name = REPORT_NAME
	created.Parent = ServerStorage

	return created
end

--[[
    The line a run gets when another run still holds the server, or nil
    when the server is free
--]]

local function refusal(label: string): string?
	local running: any = Workspace:GetAttribute(RUN_ATTRIBUTE)
	if type(running) == "string" then
		return `{label}: refused, {running} is still running`
	end

	return nil
end

--[[
    Waits out the warm-up, then samples the steady window: each Heartbeat's
    interval and Stats times, and once a second the server's send rates and
    the real player count. Returns the run's report line
--]]

local function window(label: string): string
	task.wait(WARMUP_SECONDS)

	local intervals: { number } = {}
	local heartbeatTimes: { number } = {}
	local physicsTimes: { number } = {}
	local dataSend: { number } = {}
	local physicsSend: { number } = {}
	local fewest: number = math.huge
	local most: number = 0

	-- Disconnected below, once the steady window closes
	local connection: RBXScriptConnection = RunService.Heartbeat:Connect(function (deltaTime: number)
		table.insert(intervals, deltaTime)
		table.insert(heartbeatTimes, Stats.HeartbeatTime)
		table.insert(physicsTimes, Stats.PhysicsStepTime)
	end)

	-- Every client samples its own receive rates while this is set
	Workspace:SetAttribute(STEADY_ATTRIBUTE, true)

	local started: number = os.clock()
	local deadline: number = started + STEADY_SECONDS
	while os.clock() < deadline do
		task.wait(SAMPLE_INTERVAL)

		table.insert(dataSend, Stats.DataSendKbps)
		table.insert(physicsSend, Stats.PhysicsSendKbps)

		local players: number = #Players:GetPlayers()
		fewest = math.min(fewest, players)
		most = math.max(most, players)
	end

	local elapsed: number = os.clock() - started
	connection:Disconnect()
	Workspace:SetAttribute(STEADY_ATTRIBUTE, nil)

	local frames: { number } = {}
	local rates: { number } = {}
	for _, interval: number in intervals do
		table.insert(frames, interval * MS_PER_SECOND)
		table.insert(rates, 1 / interval)
	end

	local parts: { string } = {
		`{label}: real players {fewest} to {most}`,
		`heartbeats a second {Report.number(#intervals / elapsed)}`,
		`frame ms {Report.summary(frames, PERCENTILES)}`,
		`server FPS {Report.summary(rates, { FPS_PERCENTILE })}`,
		`Stats.HeartbeatTime {Report.summary(heartbeatTimes, PERCENTILES)}`,
		`Stats.PhysicsStepTime {Report.summary(physicsTimes, PERCENTILES)}`,
		`Stats.DataSendKbps {Report.summary(dataSend, PERCENTILES)}`,
		`Stats.PhysicsSendKbps {Report.summary(physicsSend, PERCENTILES)}`,
	}

	return table.concat(parts, SEPARATOR)
end

--[[
    Appends a line to the server's report, which a short execute_luau chunk
    reads back as ServerStorage.ArmReport.Value, and prints it for the log
--]]

function Run.record(line: string)
	Report.append(reportValue(), line)
end

--[[
    Runs one measured run to its end and records its line, refused while
    another run holds the server. The load's stop runs however the window
    ends, so nothing the load made outlives its run
--]]

function Run.measure(label: string, load: Load?): (boolean, string)
	local refused: string? = refusal(label)
	if refused then
		Run.record(refused)
		return false, refused
	end

	Workspace:SetAttribute(RUN_ATTRIBUTE, label)

	local stop: (() -> ())? = nil
	local measured: boolean, result: any = pcall(function ()
		if load then
			stop = load()
		end

		return window(label)
	end)

	if stop then
		stop()
	end

	Workspace:SetAttribute(STEADY_ATTRIBUTE, nil)
	Workspace:SetAttribute(RUN_ATTRIBUTE, nil)

	local line: string = measured and result or `{label}: failed: {result}`
	Run.record(line)

	return measured, line
end

--[[
    Starts a run in its own thread and answers at once, for an execute_luau
    chunk that must return within seconds. The run's line reaches the report
    when the warm-up and the steady window have passed
--]]

function Run.start(label: string, load: Load?): (boolean, string)
	local refused: string? = refusal(label)
	if refused then
		return false, refused
	end

	task.spawn(Run.measure, label, load)

	local length: number = WARMUP_SECONDS + STEADY_SECONDS
	return true, `{label}: started, its line reaches ServerStorage.{REPORT_NAME} in about {length} s`
end

return Run
