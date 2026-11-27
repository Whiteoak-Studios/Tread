--[[
    The render times give the CPU's and GPU's frame times at each percentile
    by nearest rank, raw as Stats gives them, each with how many samples read
    0, so a time the engine left at 0 shows as such
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

-- The case's own frame values, so its answers stand whatever the dev place tunes
local FRAMES_VALUES: { [string]: any } = {
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1,
	spike = 2,
	hitch = 33.3,
}

-- 20 CPU times out of order, two of them 0 and the rest 0.003 to 0.020: the p50 is rank 10, 0.010, the p95 rank 19,
-- 0.019, and the p99 rank 20, 0.020
local CPU: { number } = {
	0.012,
	0,
	0.005,
	0.020,
	0.009,
	0.003,
	0.016,
	0.010,
	0.007,
	0.019,
	0,
	0.014,
	0.004,
	0.011,
	0.018,
	0.006,
	0.013,
	0.008,
	0.017,
	0.015,
}

local GPU_SAMPLES: number = 20 -- GPU times, every one a 0

local LINE: string = "Stats.RenderCPUFrameTime p50/p95/p99 0.01/0.019/0.02, 2 of 20 read 0, "
	.. "Stats.RenderGPUFrameTime p50/p95/p99 0/0/0, 20 of 20 read 0"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dev: any = loaded.game:GetService("ReplicatedStorage").Shared.Dev

	-- The values are set before Frames reads them as it loads
	local config: { [string]: any } = loaded.require(dev.FramesConfig)
	for key: string, value: any in FRAMES_VALUES do
		config[key] = value
	end

	local Frames: any = loaded.require(dev.Frames)

	local gpu: { number } = table.create(GPU_SAMPLES, 0)
	local line: string = Frames.render(table.clone(CPU), gpu)
	if line ~= LINE then
		return false, `Known render times gave "{line}", not "{LINE}"`
	end

	return true, nil
end
