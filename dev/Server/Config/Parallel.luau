--[[
    The parallel probes on the dev server: ParallelProbe's worker counts,
    batches, loop and waits, ParallelReturn's rounds, values and sizes,
    ParallelFrames' arms, ParallelStep's probes and ParallelBounds' loads
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

	-- ParallelFrames' arms, each on clones of its own: rounds handed out at PreSimulation or PostSimulation, and the
	-- frame event at which each round's results are first all readable on the main thread
	frames = {
		workers = 4, -- Clones each worker arm hands its rounds to
		rounds = 300, -- Rounds each arm hands out, one at a time
		spinsMs = { 1, 5 }, -- Milliseconds each worker spins a round, every worker arm run at each
		armedWait = 5, -- Seconds an arm's clones have to connect their frame callbacks
		roundWait = 1, -- Seconds a round's results have to be all seen, past which it counts as never in
		armWait = 60, -- Seconds an arm's rounds may take in all
	},

	-- ParallelStep's probes P9, P2, P7 and P3, each run on the same clones of the step worker
	step = {
		workers = 4, -- Clones of the step worker
		slots = 90, -- Parts under Workspace.TestContent that P2's queries and P7's boxes are planned beside
		boxes = 2000, -- P7's boxes at the hull's size
		smallRadius = 0.5, -- Studs, P2's smaller sphere, the other being the step's radius
		slotSeed = 2463534242, -- Where the slot pick's generator starts, a whole number from 1 to 2^32 - 1
		planSeed = 362436069, -- And P2's queries'
		boxSeed = 521288629, -- And P7's boxes'
		pieceBytes = 250000, -- The most of P2's results a clone fires back at once, under P5's largest return
		answerWait = 30, -- Seconds one probe's answers from every clone may take, past which a clone counts as silent
	},

	-- ParallelBounds' probe P10: the boxes the step's exact check is handed on bot loads, then the bounds query beside
	-- it on the main thread and on the step block's clones, with the step block's boxes, seeds, pieces and waits
	bounds = {
		loads = { "S3", "S4", "Spread150" }, -- The bot harness's scenarios sampled, one after another
		timing = { seeds = { 1 }, warmup = 5, window = 20, interval = 1 }, -- Each load's run, a bot harness Timing
		cap = 60000, -- The most boxes a load keeps, past 149 bots at 20 ticks a second through its 20 s window
		parallelBoxes = 5000, -- Each load's first boxes the clones answer too, behind P7's
	},
}
