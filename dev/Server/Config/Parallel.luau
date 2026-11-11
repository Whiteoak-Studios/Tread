--[[
    The parallel probe on the dev server: the worker counts it measures, its
    batches, the loop's size and how it is sized, and how long each wait lasts
--]]

--!strict
return {
	workers = { 1, 2, 4, 8, 16 }, -- Worker counts measured in turn, each with clones of its own
	repeats = 50, -- Batches sent at each count, and serial runs of the loop for the baseline

	workMs = 2, -- Milliseconds the loop is sized to take, run once serially on the main thread
	bytes = 4096, -- The buffer each pass of the loop goes over
	trialPasses = 20, -- Passes each sizing run times
	trials = 5, -- Sizing runs, the fastest of which sizes the loop

	readyWait = 10, -- Seconds a count's workers have to bind the topic before the count stops short
	batchWait = 1, -- Seconds a batch may be in flight before its count stops short
	runWait = 60, -- Seconds a count's batches may take in all before the count stops short
}
