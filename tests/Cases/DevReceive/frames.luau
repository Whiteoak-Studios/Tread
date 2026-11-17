--[[
    The versus run's receive line puts the frame figures and render times it
    samples each frame right after the rates, and a line crowded with
    candidates keeps them whole and leaves candidates out first
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RECEIVE: string = "dev/Client/Receive.luau"
local CONFIG: string = "dev/Client/Config.luau"
local PLAYER: string = "Mike"
local LINE_BYTES: number = 2048 -- clientCost's line, string(1..2048) in dev/Schemas/Dev.volt
local COUNTERS: number = 40 -- Readable candidates with long names, more than the line holds

-- The case's own receive and frame values, so its answers stand whatever the dev place tunes
local RECEIVE_VALUES: { [string]: any } = {
	attribute = "ClientReceive",
	interval = 1,
	longest = 90,
	percentiles = { 0.5, 0.95, 0.99 },
}

local FRAMES_VALUES: { [string]: any } = {
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1,
	spike = 2,
	hitch = 33.3,
}

-- One frame's samples: its delta in seconds, the heap in kilobytes as it began and the render CPU's and GPU's times
type Frame = { delta: number, heap: number, cpu: number, gpu: number }

-- Deltas of exactly 15.625, 62.5 and 15.625 ms, the slow one past twice the median and past 33.3 ms, after a heap drop
local FRAMES: { Frame } = {
	{ delta = 1 / 64, heap = 100, cpu = 0.004, gpu = 0 },
	{ delta = 1 / 16, heap = 90, cpu = 0.012, gpu = 0.003 },
	{ delta = 1 / 64, heap = 91, cpu = 0.006, gpu = 0 },
}

-- The line those frames and one rate sample give, a part at a time
local RATES: string = "Mike: Stats.DataReceiveKbps p50 1 p95 1 p99 1 n 1; Stats.PhysicsReceiveKbps p50 2 p95 2 p99 2 n 1; "
	.. "Stats.DataReceiveKbps + Stats.PhysicsReceiveKbps p50 3 p95 3 p99 3 n 1"
local FIGURES: string = "3 frames, FPS p10 16.0, frame ms p50/p95/p99/max 15.625/62.500/62.500/62.500, "
	.. "hitches 1 (33.33%) past 2x the median frame, 1 (33.33%) past 33.3 ms, "
	.. "of the 1 past 2x the median frame, 1 followed a heap drop, of the 1 past 33.3 ms, 1 followed a heap drop"
local RENDER: string = "Stats.RenderCPUFrameTime p50/p95/p99 0.006/0.012/0.012, 0 of 3 read 0, "
	.. "Stats.RenderGPUFrameTime p50/p95/p99 0/0.003/0.003, 2 of 3 read 0"
local LINE: string = `{RATES}; {FIGURES}; {RENDER}`

-- That line is 561 B, and of the 2,009 B the left-out note leaves, the first 9 candidates take 70 B each and the rest
-- 73 B, so 20 fit
local CUT: string = "; 20 more left out at the line's 2048 B"

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A readable StatsItem standing in under a tree, its value the one given
local function item(name: string, tree: any, value: number): { [string]: any }
	return {
		Name = name,
		Parent = tree,

		IsA = function (_: any, className: string): boolean
			return className == "StatsItem"
		end,

		GetFullName = function (_: any): string
			return `Stats.Network.{name}`
		end,

		GetValue = function (_: any): number
			return value
		end,
	}
end

-- Each frame sampled through the receive as its render step would, then one sample of the rates and candidates
local function sample(Receive: any, window: { [string]: any }, stats: { [string]: any })
	for _, frame: Frame in FRAMES do
		stats.RenderCPUFrameTime = frame.cpu
		stats.RenderGPUFrameTime = frame.gpu
		Receive.frame(window, frame.delta, frame.heap, stats)
	end

	Receive.read(window, stats)
end

local function windowOf(candidates: { any }?): { [string]: any }
	return {
		label = "case",
		data = {},
		physics = {},
		frames = {},
		heap = {},
		cpu = {},
		gpu = {},
		candidates = candidates,
		search = nil,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	-- The frame values are set before the receive's Frames reads them as it loads
	local config: { [string]: any } = loaded.require(replicated.Shared.Dev.FramesConfig)
	for key: string, value: any in FRAMES_VALUES do
		config[key] = value
	end

	-- The dev client's folder, with its Config and the receive, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Receive", folder)] = RECEIVE,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)
	load(folder.Config).receive = RECEIVE_VALUES
	local Receive: any = load(folder.Receive)

	-- 1) The frame figures and render times follow the rates, each frame's delta read in milliseconds
	local stats: { [string]: any } = { DataReceiveKbps = 1, PhysicsReceiveKbps = 2 }
	local plain: { [string]: any } = windowOf(nil)
	sample(Receive, plain, stats)

	local measured: boolean, line: string = Receive.summary(plain, PLAYER, nil)
	if not measured or line ~= LINE then
		return false, `Three frames and a sample gave {measured} with "{line}", not true with "{LINE}"`
	end

	-- 2) Crowded with candidates, the line keeps every frame figure and leaves the candidates out
	local tree: { [string]: any } = {}
	local many: { any } = {}
	for index: number = 1, COUNTERS do
		table.insert(many, item(`Received Long Counter Number {string.format("%03d", index)}`, tree, index))
	end

	stats.GetDescendants = function (_: any): { any }
		return many
	end

	local crowded: { [string]: any } = windowOf((Receive.find(stats)))
	sample(Receive, crowded, stats)

	local _, cut: string = Receive.summary(crowded, PLAYER, nil)
	local head: string = string.sub(cut, 1, #LINE)
	local tail: string = string.sub(cut, -#CUT)
	if #cut > LINE_BYTES or head ~= LINE or tail ~= CUT then
		return false, `A crowded line gave {#cut} B opening "{head}" and ending "{tail}"`
	end

	return true, nil
end
