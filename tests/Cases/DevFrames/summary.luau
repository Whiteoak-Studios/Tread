--[[
    The frame figures give a window's line with known answers by nearest
    rank: an odd count, a tie at the median, hitches past each line with the
    heap drops before them, and say so when no frame was sampled
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local NONE: string = "no frame was sampled"

-- The case's own frame values, so its answers stand whatever the dev place tunes
local FRAMES_VALUES: { [string]: any } = {
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1,
	spike = 2,
	hitch = 33.3,
}

-- 21 frames' milliseconds in window order. Sorted, nine 10s fill ranks 4 to 12, so the median, rank 11, ties at 10.
-- 20 is exactly twice it and no hitch, 25 and 30 are past twice it but under 33.3 ms, and 40 is past both. The p95 is
-- rank 20, 30, the p99 rank 21, 40, and the frame rate's p10 rank 3 from the slowest, 25 ms's 40 a second
local FRAMES: { number } = { 10, 12, 9, 10, 25, 10, 11, 10, 8, 40, 10, 13, 10, 20, 9, 10, 30, 11, 10, 12, 10 }

-- The heap in kilobytes as each frame began. It drops into the 3rd frame, a steady one, the 5th, 25 ms, the 10th,
-- 40 ms, just before the frame past the threshold, and the 18th, just after the 17th, 30 ms, which it reads flat into
local HEAP: { number } = {
	500,
	501,
	450,
	451,
	400,
	401,
	402,
	403,
	404,
	300,
	301,
	302,
	303,
	304,
	305,
	306,
	306,
	200,
	201,
	202,
	203,
}

-- What those samples give: of the 25, 40 and 30 past twice the median, the first two followed a drop, as did the 40
local LINE: string = "21 frames, FPS p10 40.0, frame ms p50/p95/p99/max 10.000/30.000/40.000/40.000, "
	.. "hitches 3 (14.29%) past 2x the median frame, 1 (4.76%) past 33.3 ms, "
	.. "of the 3 past 2x the median frame, 2 followed a heap drop, of the 1 past 33.3 ms, 1 followed a heap drop"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dev: any = loaded.game:GetService("ReplicatedStorage").Shared.Dev

	-- The values are set before Frames reads them as it loads
	local config: { [string]: any } = loaded.require(dev.FramesConfig)
	for key: string, value: any in FRAMES_VALUES do
		config[key] = value
	end

	local Frames: any = loaded.require(dev.Frames)

	-- 1) Known answers, each hitch counted against the heap at its own place
	local line: string = Frames.summary(table.clone(FRAMES), table.clone(HEAP))
	if line ~= LINE then
		return false, `Known frames gave "{line}", not "{LINE}"`
	end

	-- 2) A window that sampled no frame says so
	local empty: string = Frames.summary({}, {})
	if empty ~= NONE then
		return false, `No frames gave "{empty}", not "{NONE}"`
	end

	return true, nil
end
