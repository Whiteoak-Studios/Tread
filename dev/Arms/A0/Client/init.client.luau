--[[
    Samples this client's receive rates and the StatsItems named for receiving
    once a second and every frame through each run's steady window, keeping a
    line per run under the local player and in the log, and shows the panel
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local Config = require(ReplicatedStorage.Arm.Config)
local Frames = require(ReplicatedStorage.Shared.Dev.Frames)
local Panel = require(script.Panel)
local Report = require(ReplicatedStorage.Arm.Report)

local ClientReport: StringValue = Instance.new("StringValue") -- This client's lines, which a chunk on the Client reads

local RUN_ATTRIBUTE: string = Config.runAttribute
local STEADY_ATTRIBUTE: string = Config.steadyAttribute
local REPORT_NAME: string = Config.reportName
local SAMPLE_INTERVAL: number = Config.sampleInterval
local CLIENT_GRACE_SECONDS: number = Config.clientGraceSeconds
local PERCENTILES: { number } = Config.percentiles
local SEPARATOR: string = "; " -- Between the figures of one report line
local RECEIVING: { string } = { "receiv", "recv", "incoming" } -- What a StatsItem's lowercased name holds to be read
local MILLISECONDS: number = 1000 -- A second's, which the frame figures take each frame's delta in
local FRAME_STEP: string = "ArmFrames" -- The render step a steady window samples its frames on

-- A render step ahead of every other, as the dev client's receive binds, so each frame's heap reads as the frame begins
local FRAME_PRIORITY: number = Enum.RenderPriority.First.Value

-- A StatsItem named for receiving, read at the same samples as the two rates, as the dev client's receive reads them
type Candidate = {
	name: string, -- Its full name in the Stats tree
	item: StatsItem,
	values: { number }, -- What GetValue gave at each sample it read
	unreadable: number, -- The samples whose read errored, found it gone from the tree or gave no number
	failure: string?, -- The first of those reads' failure
}

-- Whether a StatsItem's name says it counts what this client receives
local function receiving(name: string): boolean
	local lowered: string = string.lower(name)
	for _, word: string in RECEIVING do
		if string.find(lowered, word, 1, true) then
			return true
		end
	end

	return false
end

--[[
    Every StatsItem in Stats whose name says it counts what this client
    receives, by full name, and why the tree could not be searched, nil
    when it was
--]]

local function find(): ({ Candidate }, string?)
	local searched: boolean, descendants: any = pcall(Stats.GetDescendants, Stats)
	if not searched then
		return {}, tostring(descendants)
	end

	local found: { Candidate } = {}
	for _, instance: Instance in descendants do
		if instance:IsA("StatsItem") and receiving(instance.Name) then
			local item: StatsItem = instance :: StatsItem
			table.insert(found, { name = item:GetFullName(), item = item, values = {}, unreadable = 0, failure = nil })
		end
	end

	table.sort(found, function (first: Candidate, second: Candidate): boolean
		return first.name < second.name
	end)

	return found, nil
end

-- One read of a candidate: kept when it gives a number, else counted unreadable with the first failure kept
local function readItem(candidate: Candidate)
	local item: StatsItem = candidate.item
	local read: boolean, value: any = false, "it has left the Stats tree"
	if item.Parent ~= nil then
		read, value = pcall(item.GetValue, item)
	end

	if read and type(value) == "number" then
		table.insert(candidate.values, value)
		return
	end

	candidate.unreadable += 1
	if not candidate.failure then
		candidate.failure = read and `GetValue gave a {typeof(value)}` or tostring(value)
	end
end

--[[
    The candidates' figures, each by name: its summary, or once any read
    failed, how many did and the first's failure, a tree that could not be
    searched or held none saying so instead
--]]

local function candidateParts(candidates: { Candidate }, search: string?): { string }
	if search then
		return { `Stats unsearchable for StatsItems: {search}` }
	elseif #candidates == 0 then
		return { "no StatsItem in Stats is named for receiving" }
	end

	local parts: { string } = {}
	for _, candidate: Candidate in candidates do
		if candidate.unreadable > 0 then
			local reads: number = candidate.unreadable + #candidate.values
			table.insert(
				parts,
				`{candidate.name} unreadable in {candidate.unreadable} of {reads} reads: {candidate.failure}`
			)
		else
			table.insert(parts, `{candidate.name} {Report.summary(candidate.values, PERCENTILES)}`)
		end
	end

	return parts
end

--[[
    Reads both rates and every candidate once a second until the server
    closes the run's steady window, or until its own deadline past the
    window's length passes, and gives the rates and their sum sample by
    sample
--]]

local function steady(label: string, seconds: number, candidates: { Candidate }): ({ number }, { number }, { number })
	local received: { number } = {}
	local physics: { number } = {}
	local total: { number } = {}

	local deadline: number = os.clock() + seconds + CLIENT_GRACE_SECONDS
	while os.clock() < deadline do
		task.wait(SAMPLE_INTERVAL)

		if Workspace:GetAttribute(STEADY_ATTRIBUTE) == nil or Workspace:GetAttribute(RUN_ATTRIBUTE) ~= label then
			break
		end

		local data: number = Stats.DataReceiveKbps
		local physical: number = Stats.PhysicsReceiveKbps
		table.insert(received, data)
		table.insert(physics, physical)
		table.insert(total, data + physical)

		for _, candidate: Candidate in candidates do
			readItem(candidate)
		end
	end

	return received, physics, total
end

--[[
    Samples a run's steady window once a second and every frame, then
    records the run's line: data and physics receive, their sum sample by
    sample, the frame figures and, once a frame was sampled, the render
    times, then every candidate read at the same samples
--]]

local function sample(label: string, seconds: number)
	local frames: { number } = {}
	local heap: { number } = {}
	local cpu: { number } = {}
	local gpu: { number } = {}
	local candidates: { Candidate }, search: string? = find()

	-- Unbound as soon as steady returns, so every way the sampling ends unbinds it
	RunService:BindToRenderStep(FRAME_STEP, FRAME_PRIORITY, function (delta: number)
		table.insert(heap, gcinfo())
		table.insert(frames, delta * MILLISECONDS)
		table.insert(cpu, Stats.RenderCPUFrameTime)
		table.insert(gpu, Stats.RenderGPUFrameTime)
	end)

	local received: { number }, physics: { number }, total: { number } = steady(label, seconds, candidates)
	RunService:UnbindFromRenderStep(FRAME_STEP)

	local parts: { string } = {
		`{label} client {Player.Name}: real players {#Players:GetPlayers()}`,
		`Stats.DataReceiveKbps {Report.summary(received, PERCENTILES)}`,
		`Stats.PhysicsReceiveKbps {Report.summary(physics, PERCENTILES)}`,
		`Stats.DataReceiveKbps + Stats.PhysicsReceiveKbps {Report.summary(total, PERCENTILES)}`,
		Frames.summary(frames, heap),
	}

	if #cpu > 0 then
		table.insert(parts, Frames.render(cpu, gpu))
	end

	for _, part: string in candidateParts(candidates, search) do
		table.insert(parts, part)
	end

	Report.append(ClientReport, table.concat(parts, SEPARATOR))
end

--[[
    Starts sampling when the server has opened a run's steady window, which
    it holds open for the seconds its attribute gives
--]]

local function watch()
	local label: any = Workspace:GetAttribute(RUN_ATTRIBUTE)
	local seconds: any = Workspace:GetAttribute(STEADY_ATTRIBUTE)
	if type(seconds) == "number" and type(label) == "string" then
		task.spawn(sample, label, seconds)
	end
end

ClientReport.Name = REPORT_NAME
ClientReport.Parent = Player

-- Lives for the client session, like a controller's Init listener, so it keeps no disconnect
Workspace:GetAttributeChangedSignal(STEADY_ATTRIBUTE):Connect(watch)

-- A client that joins during a steady window samples the rest of it
watch()

-- Last, since it waits at boot for the PlayerGui and the server's report
Panel.start(ClientReport)
