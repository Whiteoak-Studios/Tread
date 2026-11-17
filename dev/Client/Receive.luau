--[[
    The versus run's client side: while the Workspace attribute names a
    window, samples every frame, and this client's receive rates and the
    StatsItems named for receiving each interval, then sends its line
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local Network = require(ReplicatedStorage.Shared.Network.Client)

local Frames = require(ReplicatedStorage.Shared.Dev.Frames)
local ReceiveConfig = require(script.Parent.Config).receive

local ATTRIBUTE: string = ReceiveConfig.attribute
local INTERVAL: number = ReceiveConfig.interval
local LONGEST: number = ReceiveConfig.longest
local PERCENTILES: { number } = ReceiveConfig.percentiles
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local FIGURE: string = "%.4g" -- Four significant digits, as the A0 arm's client prints its rates
local SEPARATOR: string = "; " -- Between the figures of one line, as the A0 arm's client puts them
local DATA: string = "Stats.DataReceiveKbps" -- Each figure's name as the A0 arm's client prints it
local PHYSICS: string = "Stats.PhysicsReceiveKbps"
local RECEIVING: { string } = { "receiv", "recv", "incoming" } -- What a StatsItem's lowercased name holds to be read
local LINE_BYTES: number = 2048 -- The most clientCost's line carries, string(1..2048) in dev/Schemas/Dev.volt
local MILLISECONDS: number = 1000 -- A second's, which the frame figures take each frame's delta in
local FRAME_STEP: string = "DevReceiveFrames" -- The render step an open window samples its frames on

-- A render step, as Tread's client frame is, ahead of every other, so each frame's heap reads as the frame begins
local FRAME_PRIORITY: number = Enum.RenderPriority.First.Value

-- A StatsItem named for receiving, read at the same samples as the two rates
export type Candidate = {
	name: string, -- Its full name in the Stats tree
	item: StatsItem,
	values: { number }, -- What GetValue gave at each sample it read
	unreadable: number, -- The samples whose read errored, found it gone from the tree or gave no number
	failure: string?, -- The first of those reads' failure
}

-- What one window sampled: both rates and every candidate read together once each interval, and every frame
export type Window = {
	label: string,
	data: { number }, -- Stats.DataReceiveKbps at each sample
	physics: { number }, -- Stats.PhysicsReceiveKbps at the same samples
	frames: { number }, -- Milliseconds of each frame from the window's open to its close, its delta
	heap: { number }, -- Kilobytes of Luau heap as each frame began
	cpu: { number }, -- Stats.RenderCPUFrameTime at each frame
	gpu: { number }, -- Stats.RenderGPUFrameTime at each frame
	candidates: { Candidate }?, -- Nil for a window that looked for none
	search: string?, -- Why the Stats tree could not be searched for them, nil when it was
}

local Running: boolean = false
local Open: Window? = nil -- The window sampling, nil between windows

local Receive = {}

-- A rate's percentiles and its samples counted, as the A0 arm's client prints them. It sorts the list in place
local function spread(samples: { number }): string
	local parts: { string } = {}
	for _, share: number in PERCENTILES do
		local figure: string = string.format(FIGURE, Frames.percentile(samples, share))
		table.insert(parts, `p{math.round(share * PERCENT)} {figure}`)
	end

	table.insert(parts, `n {#samples}`)

	return table.concat(parts, " ")
end

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
    Every StatsItem in the Stats tree given whose name says it counts what
    this client receives, by full name, and why the tree could not be
    searched, nil when it was
--]]

function Receive.find(stats: Stats): ({ Candidate }, string?)
	local searched: boolean, descendants: any = pcall(stats.GetDescendants, stats)
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
    Takes one sample of the window from the Stats given: both rates, then
    each candidate, whose failed read is counted unreadable rather than
    stopping the sample
--]]

function Receive.read(window: Window, stats: Stats)
	table.insert(window.data, stats.DataReceiveKbps)
	table.insert(window.physics, stats.PhysicsReceiveKbps)

	local candidates: { Candidate }? = window.candidates
	if candidates then
		for _, candidate: Candidate in candidates do
			readItem(candidate)
		end
	end
end

--[[
    Takes one frame's sample of the window: the heap in kilobytes as the
    frame began, read before anything else in it, its delta in seconds, and
    the render CPU's and GPU's frame times from the Stats given
--]]

function Receive.frame(window: Window, delta: number, kilobytes: number, stats: Stats)
	table.insert(window.heap, kilobytes)
	table.insert(window.frames, delta * MILLISECONDS)
	table.insert(window.cpu, stats.RenderCPUFrameTime)
	table.insert(window.gpu, stats.RenderGPUFrameTime)
end

-- A candidate's figure: its percentiles and count, or once any read failed, how many did and the first's failure
local function candidatePart(candidate: Candidate): string
	if candidate.unreadable > 0 then
		local reads: number = candidate.unreadable + #candidate.values
		return `{candidate.name} unreadable in {candidate.unreadable} of {reads} reads: {candidate.failure}`
	end

	return `{candidate.name} {spread(candidate.values)}`
end

--[[
    The line with the candidates after it, readable ones first and each by
    name, a tree that could not be searched or held none saying so instead.
    Each is added while the line stays within the bytes given, and once one
    is left out every later one is, their count ending the line
--]]

local function withCandidates(line: string, window: Window, candidates: { Candidate }, limit: number): string
	local parts: { string } = {}
	local search: string? = window.search

	if search then
		table.insert(parts, `Stats unsearchable for StatsItems: {search}`)
	elseif #candidates == 0 then
		table.insert(parts, "no StatsItem in Stats is named for receiving")
	end

	local ordered: { Candidate } = table.clone(candidates)
	table.sort(ordered, function (first: Candidate, second: Candidate): boolean
		if (first.unreadable == 0) ~= (second.unreadable == 0) then
			return first.unreadable == 0
		end

		return first.name < second.name
	end)

	for _, candidate: Candidate in ordered do
		table.insert(parts, candidatePart(candidate))
	end

	local function note(count: number): string
		return `{SEPARATOR}{count} more left out at the line's {LINE_BYTES} B`
	end

	local room: number = limit - #note(#parts)
	local left: number = 0
	for _, part: string in parts do
		local added: string = `{line}{SEPARATOR}{part}`
		if left == 0 and #added <= room then
			line = added
		else
			left += 1
		end
	end

	if left > 0 then
		line = `{line}{note(left)}`
	end

	return line
end

--[[
    A window's line and whether it measured: the player, then the data and
    physics receive rates and their sum taken sample by sample, each at its
    percentiles with its count, then the frame figures and, once a frame was
    sampled, the render times, then the candidates within clientCost's
    bytes, so those are the first left out. A window with no sample measured
    nothing, and one a failure ended is unmeasured with the failure after
    its line. It sorts its lists in place
--]]

function Receive.summary(window: Window, player: string, failure: string?): (boolean, string)
	local measured: boolean = #window.data > 0
	local line: string = `{player}: no receive rate was sampled, so the window measured nothing`
	local ending: string = failure and `, then {failure}` or ""

	if measured then
		-- Summed before either list is sorted, so each sum pairs the two rates one sample read
		local sums: { number } = {}
		for index: number, data: number in window.data do
			table.insert(sums, data + window.physics[index])
		end

		local parts: { string } = {
			`{player}: {DATA} {spread(window.data)}`,
			`{PHYSICS} {spread(window.physics)}`,
			`{DATA} + {PHYSICS} {spread(sums)}`,
			Frames.summary(window.frames, window.heap),
		}

		if #window.cpu > 0 then
			table.insert(parts, Frames.render(window.cpu, window.gpu))
		end

		line = table.concat(parts, SEPARATOR)

		local candidates: { Candidate }? = window.candidates
		if candidates then
			line = withCandidates(line, window, candidates, LINE_BYTES - #ending)
		end
	end

	if failure then
		return false, `{line}{ending}`
	end

	return measured, line
end

-- Ends the open window and its render step, and sends its line, unmeasured with the failure when one ended it
local function finish(failure: string?)
	local window: Window? = Open
	if not window then
		return
	end

	Open = nil
	RunService:UnbindFromRenderStep(FRAME_STEP)

	local measured: boolean, line: string = Receive.summary(window, Player.Name, failure)
	Network.clientCost.fire(window.label, measured, line)
end

--[[
    Samples a window once each interval while it is the one open, and ends
    it once its deadline passes with the attribute still naming it
--]]

local function sample(window: Window)
	local deadline: number = os.clock() + LONGEST

	while Open == window do
		task.wait(INTERVAL)

		if Open ~= window then
			return
		elseif os.clock() >= deadline then
			return finish(`it passed its {LONGEST} s deadline with {ATTRIBUTE} still set`)
		end

		Receive.read(window, Stats)
	end
end

-- The attribute changed: a window it no longer names ends, and a label it now holds opens one
local function changed()
	local label: any = Workspace:GetAttribute(ATTRIBUTE)
	local window: Window? = Open
	if window and label ~= window.label then
		finish(nil)
	end

	if type(label) == "string" and not Open then
		local candidates: { Candidate }, search: string? = Receive.find(Stats)
		local opened: Window = {
			label = label,
			data = {},
			physics = {},
			frames = {},
			heap = {},
			cpu = {},
			gpu = {},
			candidates = candidates,
			search = search,
		}

		Open = opened

		-- Unbound by finish, which every way a window ends runs
		RunService:BindToRenderStep(FRAME_STEP, FRAME_PRIORITY, function (delta: number)
			Receive.frame(opened, delta, gcinfo(), Stats)
		end)

		task.spawn(sample, opened)
	end
end

--[[
    Starts the receive rates once a client. Its listener lives for the
    client session, and each window's render step and sampling end with
    the window
--]]

function Receive.start()
	if Running then
		error("Receive.start runs once a client, and it has already run", 2)
	end

	Running = true
	Workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(changed)
end

return Receive
