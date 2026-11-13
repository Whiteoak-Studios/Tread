--[[
    Samples this client's own receive rates once a second through each run's
    steady window, keeping a line per run under the local player and in the
    client log
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local Config = require(ReplicatedStorage.Arm.Config)
local Report = require(ReplicatedStorage.Arm.Report)

local ClientReport: StringValue = Instance.new("StringValue") -- This client's lines, which a chunk on the Client reads

local RUN_ATTRIBUTE: string = Config.runAttribute
local STEADY_ATTRIBUTE: string = Config.steadyAttribute
local REPORT_NAME: string = Config.reportName
local STEADY_SECONDS: number = Config.steadySeconds
local SAMPLE_INTERVAL: number = Config.sampleInterval
local CLIENT_GRACE_SECONDS: number = Config.clientGraceSeconds
local PERCENTILES: { number } = Config.percentiles
local SEPARATOR: string = "; " -- Between the figures of one report line

--[[
    Samples once a second until the server closes the run's steady window,
    or until its own deadline passes, then records the run's line
--]]

local function sample(label: string)
	local received: { number } = {}
	local physics: { number } = {}

	local deadline: number = os.clock() + STEADY_SECONDS + CLIENT_GRACE_SECONDS
	while os.clock() < deadline do
		task.wait(SAMPLE_INTERVAL)

		if Workspace:GetAttribute(STEADY_ATTRIBUTE) ~= true or Workspace:GetAttribute(RUN_ATTRIBUTE) ~= label then
			break
		end

		table.insert(received, Stats.DataReceiveKbps)
		table.insert(physics, Stats.PhysicsReceiveKbps)
	end

	local parts: { string } = {
		`{label} client {Player.Name}: real players {#Players:GetPlayers()}`,
		`Stats.DataReceiveKbps {Report.summary(received, PERCENTILES)}`,
		`Stats.PhysicsReceiveKbps {Report.summary(physics, PERCENTILES)}`,
	}

	Report.append(ClientReport, table.concat(parts, SEPARATOR))
end

--[[
    Starts sampling when the server has opened a run's steady window
--]]

local function watch()
	local label: any = Workspace:GetAttribute(RUN_ATTRIBUTE)
	if Workspace:GetAttribute(STEADY_ATTRIBUTE) == true and type(label) == "string" then
		task.spawn(sample, label)
	end
end

ClientReport.Name = REPORT_NAME
ClientReport.Parent = Player

-- Lives for the client session, like a controller's Init listener, so it keeps no disconnect
Workspace:GetAttributeChangedSignal(STEADY_ATTRIBUTE):Connect(watch)

-- A client that joins during a steady window samples the rest of it
watch()
