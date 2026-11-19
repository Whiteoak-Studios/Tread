--[[
    The frame figures both arms' client lines print, from each frame's delta
    and the heap as it began: the frame rate and times, the hitches, the heap
    drops before them, and the render CPU's and GPU's frame times
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FramesConfig = require(ReplicatedStorage.Shared.Dev.FramesConfig)

local PERCENTILES: { number } = FramesConfig.percentiles
local FPS: number = FramesConfig.fps
local SPIKE: number = FramesConfig.spike
local HITCH: number = FramesConfig.hitch
local MILLISECONDS: number = 1000 -- A second's, which a summary takes each frame's delta in
local PERCENT: number = 100 -- Turns a share into the number a pNN label shows
local MEDIAN: number = 0.5 -- The share the median frame is read at
local WORST: number = 1 -- The share whose nearest rank is the largest sample
local RATE_FIGURE: string = "%.1f" -- Frames a second as a line prints them
local TIME_FIGURE: string = "%.3f" -- Milliseconds as a line prints them
local SHARE_FIGURE: string = "%.2f%%" -- A share of the window's frames as a line prints it
local RAW_FIGURE: string = "%.4g" -- Four significant digits, for the render times, whose units are unproven
local CPU: string = "Stats.RenderCPUFrameTime" -- Each render time's name as a line prints it
local GPU: string = "Stats.RenderGPUFrameTime"
local NONE: string = "no frame was sampled" -- The frame figures of a window that sampled none

-- The frames past each hitch line, each by its place in the window
export type Slow = {
	pastMedian: { number }, -- Past the median's multiple
	pastHitch: { number }, -- Past the threshold
}

local Frames = {}

Frames.pastMedian = `{SPIKE}x the median frame` -- Each hitch line as a line names it
Frames.pastHitch = `{HITCH} ms`

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
function Frames.percentile(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

-- Each share's pNN label, joined as a line prints them
function Frames.labels(shares: { number }): string
	local labels: { string } = {}
	for _, share: number in shares do
		table.insert(labels, `p{math.round(share * PERCENT)}`)
	end

	return table.concat(labels, "/")
end

-- The samples at each share by nearest rank, in the figure given, joined as a line prints them. It sorts the list
function Frames.spread(samples: { number }, shares: { number }, form: string): string
	local figures: { string } = {}
	for _, share: number in shares do
		table.insert(figures, string.format(form, Frames.percentile(samples, share)))
	end

	return table.concat(figures, "/")
end

-- Frames a second from a frame's delta in seconds, which must be above 0
function Frames.rate(delta: number): number
	return 1 / delta
end

--[[
    The frames past the median's multiple and past the threshold, each by
    its place, the median read from a copy so the list keeps its order
--]]

function Frames.slow(frames: { number }): Slow
	local median: number = Frames.percentile(table.clone(frames), MEDIAN)
	local slow: Slow = { pastMedian = {}, pastHitch = {} }

	for index: number, frame: number in frames do
		if frame > SPIKE * median then
			table.insert(slow.pastMedian, index)
		end

		if frame > HITCH then
			table.insert(slow.pastHitch, index)
		end
	end

	return slow
end

-- Whether the heap read lower as the frame at the place given began than as the one before it began
function Frames.dropped(heap: { number }, index: number): boolean
	return index > 1 and heap[index] < heap[index - 1]
end

-- The frames counted and the frame rate at its low share, as a line prints them. It sorts the rates in place
function Frames.counted(count: number, rates: { number }): string
	local rate: string = string.format(RATE_FIGURE, Frames.percentile(rates, FPS))

	return `{count} frames, FPS p{math.round(FPS * PERCENT)} {rate}`
end

-- The frame times at each percentile and their worst, as a line prints them. It sorts the list in place
function Frames.times(frames: { number }): string
	local spread: string = Frames.spread(frames, PERCENTILES, TIME_FIGURE)
	local worst: string = string.format(TIME_FIGURE, Frames.percentile(frames, WORST))

	return `frame ms {Frames.labels(PERCENTILES)}/max {spread}/{worst}`
end

-- A count of a window's frames as a share of them all, as a line prints it
local function share(count: number, total: number): string
	return string.format(SHARE_FIGURE, count / total * PERCENT)
end

-- The hitches past each line, each with its share of the frames counted, as a line prints them
function Frames.hitches(pastMedian: number, pastHitch: number, count: number): string
	local spiked: string = `hitches {pastMedian} ({share(pastMedian, count)}) past {Frames.pastMedian}`

	return `{spiked}, {pastHitch} ({share(pastHitch, count)}) past {Frames.pastHitch}`
end

-- How many of the frames at the places given followed a heap drop
local function drops(places: { number }, heap: { number }): number
	local count: number = 0
	for _, index: number in places do
		if Frames.dropped(heap, index) then
			count += 1
		end
	end

	return count
end

--[[
    A window's frame figures from each frame's delta in milliseconds and the
    heap in kilobytes as it began, as ClientCost's line prints them for the
    same samples: the frames and the frame rate, the frame times, the
    hitches past each line, and how many of each set followed a heap drop.
    It sorts the frames in place
--]]

function Frames.summary(frames: { number }, heap: { number }): string
	local count: number = #frames
	if count == 0 then
		return NONE
	end

	local rates: { number } = {}
	for _, frame: number in frames do
		if frame > 0 then
			table.insert(rates, Frames.rate(frame / MILLISECONDS))
		end
	end

	-- Read before the frame times sort the list, so each hitch keeps its place beside the heap
	local slow: Slow = Frames.slow(frames)
	local spiked: number, hitched: number = #slow.pastMedian, #slow.pastHitch
	local medianDrops: number, hitchDrops: number = drops(slow.pastMedian, heap), drops(slow.pastHitch, heap)

	local figures: { string } = {
		Frames.counted(count, rates),
		Frames.times(frames),
		Frames.hitches(spiked, hitched, count),
		`of the {spiked} past {Frames.pastMedian}, {medianDrops} followed a heap drop`,
		`of the {hitched} past {Frames.pastHitch}, {hitchDrops} followed a heap drop`,
	}

	return table.concat(figures, ", ")
end

-- How many of the samples read 0, so a time the engine leaves at 0 reads as such rather than as no time spent
local function zeros(samples: { number }): number
	local count: number = 0
	for _, sample: number in samples do
		if sample == 0 then
			count += 1
		end
	end

	return count
end

-- One render time at each percentile with its zero reads, as a line prints it. It sorts the list in place
local function renderTime(name: string, samples: { number }): string
	local read: string = `{zeros(samples)} of {#samples} read 0`

	return `{name} {Frames.labels(PERCENTILES)} {Frames.spread(samples, PERCENTILES, RAW_FIGURE)}, {read}`
end

--[[
    The render CPU's and GPU's frame times at each percentile, as Stats
    gives them beside each frame's delta, raw since their units are
    unproven, each with how many samples read 0. It sorts both lists
--]]

function Frames.render(cpu: { number }, gpu: { number }): string
	return `{renderTime(CPU, cpu)}, {renderTime(GPU, gpu)}`
end

return Frames
