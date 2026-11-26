--[[
    The live runs' numbers on the dev server: the rate a run is asked for,
    the report's size, its wait for the verdict line and its pieces, the
    lines it leaves out, and where its reports are saved
--]]

--!strict
return {
	rate = { perSecond = 1, burst = 2 }, -- Run asks a second, where a click on the panel sends one

	pieceBytes = 4000, -- Bytes each piece of a report carries at most, the runReport event's own bound in Dev.volt
	reportBytes = 32000, -- Bytes of a run's Output the report keeps, past which it gives the count cut and the verdict
	verdictWait = 5, -- Seconds after a run returns the report waits for the Runner's verdict line to reach it

	-- The bot run's per-second lines and G8's per-episode lines, too many to paste, and each step benchmark half's
	-- summary and relay clocks, whose figures its tables carry, and its mode, whose workers its header names, so the
	-- step benchmark's report stays under the panel's limits
	dropped = {
		"^Bots %S+ seed %d+ second %d+: ",
		"^G8 %a+ %a+ late reveal: ",
		"^Bots %S+/before seed %d+ summary over ",
		"^Bots %S+/after seed %d+ summary over ",
		"^Bots %S+/first seed %d+ summary over ",
		"^Bots %S+/second seed %d+ summary over ",
		"^Bots %S+/before seed %d+ relay clocks, ",
		"^Bots %S+/after seed %d+ relay clocks, ",
		"^Bots %S+/first seed %d+ relay clocks, ",
		"^Bots %S+/second seed %d+ relay clocks, ",
		"^Bots %S+/before seed %d+ mode: ",
		"^Bots %S+/after seed %d+ mode: ",
		"^Bots %S+/first seed %d+ mode: ",
		"^Bots %S+/second seed %d+ mode: ",
	},

	-- The single runs whose report is saved too, as each of Run all's is, under the run's start time and its name
	saved = {
		"BenchStep",
		"BenchStepNoise",
		"BenchStepMemory",
		"BenchStepSplit",
		"BenchStepNpcs",
		"BenchStepLevers",
		"BenchStepNear",
		"ClientParallel",
		"ParallelFrames",
		"ParallelStep",
		"ParallelBounds",
	},

	-- The Run all queue's reports, each saved to the experience's DataStore under the queue's start time
	queue = {
		store = "LiveRuns", -- The DataStore's name
		tries = 3, -- Writes of one key before its failure is reported
		retryWait = 3, -- Seconds between them, so the tries span the DataStore's wait between writes of one key
	},
}
