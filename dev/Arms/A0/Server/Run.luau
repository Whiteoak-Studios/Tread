--[[
    Measures one run on an arm's server: times the server's speed, starts its
    load, waits out the warm-up, samples the steady window and records the
    run's report lines
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Calibration = require(ServerScriptService.Server.Calibration)
local Config = require(ReplicatedStorage.Arm.Config)
local Report = require(ReplicatedStorage.Arm.Report)

local RUN_ATTRIBUTE: string = Config.runAttribute
local STEADY_ATTRIBUTE: string = Config.steadyAttribute
local REPORT_NAME: string = Config.reportName
local SAMPLE_INTERVAL: number = Config.sampleInterval
local PERCENTILES: { number } = Config.percentiles
local FPS_PERCENTILE: number = Config.fpsPercentile
local MS_PER_SECOND: number = 1000
local SEPARATOR: string = "; " -- Between the figures of one report line

local Types = require(ReplicatedStorage.Arm.Types)

type Load = Types.Load
type Program = Types.Program

local Run = {}

--[[
    The server's report, a StringValue in ReplicatedStorage, so every client
    can show it, holding a line per run and per settings check, made the
    first time a line is recorded
--]]

local function reportValue(): StringValue
	local report = ReplicatedStorage:FindFirstChild(REPORT_NAME) :: StringValue?
	if report then
		return report
	end

	local created: StringValue = Instance.new("StringValue")
	created.Name = REPORT_NAME
	created.Parent = ReplicatedStorage

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
    Waits out the program's warm-up, then samples its steady window: each
    Heartbeat's interval and Stats times, and once a second the server's
    send rates and the real player count. Returns the run's report line
--]]

local function window(label: string, program: Program): string
	task.wait(program.warmupSeconds)

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

	-- Every client samples its own receive rates while this holds the window's length
	Workspace:SetAttribute(STEADY_ATTRIBUTE, program.steadySeconds)

	local started: number = os.clock()
	local deadline: number = started + program.steadySeconds
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
    reads back as ReplicatedStorage.ArmReport.Value, and prints it for the log
--]]

function Run.record(line: string)
	Report.append(reportValue(), line)
end

--[[
    Runs one measured run to its end on the program's timing and records its
    lines, refused while another run holds the server. The calibration comes
    first, and a failed one's line says why while the run goes on. The load's
    stop runs however the window ends, so nothing the load made outlives it
--]]

function Run.measure(label: string, load: Load?, program: Program): (boolean, string)
	local refused: string? = refusal(label)
	if refused then
		Run.record(refused)
		return false, refused
	end

	Workspace:SetAttribute(RUN_ATTRIBUTE, label)

	local stop: (() -> ())? = nil
	local measured: boolean, result: any = pcall(function ()
		-- Before the load, so it times nothing the load does
		local _: boolean, calibration: string = Calibration.run()
		Run.record(`{label} calibration: {calibration}`)

		if load then
			stop = load()
		end

		return window(label, program)
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
    when its calibration, spawn, warm-up and steady window have passed
--]]

function Run.start(label: string, load: Load?, program: Program): (boolean, string)
	local refused: string? = refusal(label)
	if refused then
		return false, refused
	end

	task.spawn(Run.measure, label, load, program)

	local length: number = program.warmupSeconds + program.steadySeconds
	return true, `{label}: started, its line reaches ReplicatedStorage.{REPORT_NAME} about {length} s after its spawn`
end

return Run
