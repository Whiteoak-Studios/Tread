--[[
    The parallel probes on the dev server: ParallelProbe's worker counts,
    batches, loop and waits, and ParallelReturn's rounds, values, sizes and
    waits, each wait a count's or a probe's own
--]]

--!strict
return {
	workers = { 1, 2, 4, 8, 16 }, -- Worker counts measured in turn, each with clones of its own
	repeats = 50, -- Batches sent at each count, and serial runs of the loop for the baseline

	workMs = 2, -- Milliseconds the loop is sized to take, run once serially on the main thread
	bytes = 4096, -- The buffer each pass of the loop goes over
	trialPasses = 20, -- Passes each sizing run times
	trials = 5, -- Sizing runs, the fastest of which sizes the loop

	readyWait = 10, -- Seconds a pool's workers have to bind their topics before it stops short
	batchWait = 1, -- Seconds a batch may be in flight before its count stops short
	runWait = 60, -- Seconds a count's batches may take in all before the count stops short

	-- ParallelReturn's three probes, P1 when results come back, P4 what crosses VMs and P5 what sizes cost
	returns = {
		workers = 8, -- P1's workers sent a round each Heartbeat, beside one more running the ConnectParallel arm
		heartbeats = 600, -- P1's rounds, one sent at each Heartbeat
		mainMs = 5, -- Milliseconds the main thread's busy loop holds each Heartbeat before P1's sends
		workerMs = 1, -- Milliseconds each P1 worker spins a round
		roundsWait = 30, -- Seconds P1's rounds may take to send in all
		drainWait = 2, -- Seconds after P1's last round for its late events

		echoKilobytes = 100, -- P4's buffers and string, and the buffer and string a worker writes into a SharedTable
		echoBuffers = 3, -- Buffers in P4's table of buffers
		echoWait = 2, -- Seconds each P4 value, and the SharedTable writes, have to come back

		sendKilobytes = { 1, 10, 40, 100, 400 }, -- P5's SendMessage payloads
		sendWorkers = { 1, 2, 4, 8 }, -- Workers each P5 payload is sent to, in turn
		returnKilobytes = { 10, 100, 300, 1000 }, -- P5's returns, by BindableEvent and by SharedTable
		pieces = 250, -- Exact-length buffers each P5 return is copied into
		repeats = 30, -- P5's rounds at each size and worker count
		roundWait = 1, -- Seconds a P5 round may be in flight before its row stops short
	},
}
