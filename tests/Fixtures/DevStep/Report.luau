--[[
    A step benchmark half's Output as a live server's Spread150 half on the
    relay's workers prints it, under the half's own name, with its real
    player and any relay clocks, and figures the size its rows print at
--]]

--!strict
local SEPARATOR: string = "; " -- Between the parts of one line
local COMMA: string = ", " -- Between the clauses of one part
local CLOCK: string = "0.123/0.456/0.789" -- Each relay clock's p50, p95 and p99 as a live read prints them
local ACROSS: string = "delivery and back across a worker's clock and the main thread's"
local BY_PLACE: string = "Tread ms a Heartbeat by its place in the tick, p50/p95, less the bots' stage"
local SUMMED: string = "decode + simulate + npcs + history + relay + finish"

-- The parts of the summary a read with no clocks gives, as the live half's printed them
local SUMMARY: { string } = {
	"antiEspFailOpens 0.000/0.000/0.000",
	"antiEspHidden 880.000/1073.000/1114.000",
	"antiEspLyingTests 0.000/0.000/0.000",
	"antiEspLyingWaiting 0.000/0.000/0.000",
	"antiEspMs 1.988/2.007/2.026",
	"antiEspP95Ms 2.008/2.013/2.014",
	"antiEspTests 6708.000/7209.000/7297.000",
	"bodies 0.000/0.000/0.000",
	"botsMs 3.713/4.126/4.332",
	"botsP95Ms 4.161/4.258/4.272",
	"bytesOut 421977.000/433810.000/435944.000",
	"decodeMs 1.328/1.514/1.766",
	"decodeP95Ms 1.534/1.563/1.567",
	"dropped 0.000/0.000/0.000",
	"fixturesMs 0.020/0.028/0.051",
	"fixturesP95Ms 0.028/0.032/0.033",
	"historyBytes 601272.000/601272.000/601272.000",
	"historyMs 0.346/0.434/0.458",
	"historyP95Ms 0.429/0.440/0.442",
	"late 0.000/0.000/0.000",
	"npcs 0.000/0.000/0.000",
	"npcsMs 0.049/0.065/0.087",
	"npcsP95Ms 0.065/0.068/0.069",
	"players 150.000/150.000/150.000",
	"recordsCut 0.000/0.000/0.000",
	"recordsSent 28720.000/30335.000/30567.000",
	"relayDropped 0.000/0.000/0.000",
	"relayMs 4.325/4.892/5.137",
	"relayP95Ms 4.925/5.065/5.072",
	"relaySkipped 0.000/0.000/0.000",
	"seconds 1.016/1.020/1.021",
	"simulateMs 4.781/5.461/5.913",
	"simulateP95Ms 5.479/5.658/5.658",
	"standIns 0.000/0.000/0.000",
	"ticks 20.000/21.000/21.000",
	"trafficLargest 3470.000/3624.000/3752.000",
	"trafficP95 3252.000/3398.000/3472.000",
	"viewerBytes 2674.000/3052.000/3288.000",
}

local Report = {}

--[[
    One half's lines in the order a run prints them, its calibration, its
    start, mode, server, Heartbeat, tick, counts, real player and any
    clocks lines, its group's and its summary, the clocks given by name in
    the relay's order
--]]

function Report.half(run: string, clocks: { string }?): { string }
	local label: string = `Bots {run} seed 1`

	local calibration: { string } = {
		`Bots {run} calibration: native loop µs a pass of 1024 B p50/p95 13.310/16.091`,
		"Blockcast µs a cast p50/p95 2.264/3.102",
		"400 samples each over 1.637 s at 61.09 Heartbeats a second",
	}

	local start: { string } = {
		`{label}: starting with 1 real players in`,
		"outOfView on",
		"changes on",
		"1 floors laid",
		"0 NPCs awake",
		"0 sleepers made of 0",
		"its areas moved 3835",
		"0.5",
		"-70",
	}

	local server: { string } = {
		`{label} server: 59.97 Heartbeats a second`,
		"frame ms p50/p95/p99 16.68/19.44/21.3",
		"server FPS p10 53.24",
		"Stats.HeartbeatTime p50/p95/p99 0.01049/0.01096/0.01119",
		"Stats.PhysicsStepTime p50/p95/p99 4.082e-05/4.502e-05/4.791e-05",
		"Stats.DataSendKbps p50/p95/p99 3.565/3.863/3.976",
	}

	local heartbeats: { string } = {
		`{label} {BY_PLACE}: the tick's Heartbeat 12.825/14.129 with the bots' stage 0.000/0.000 over 2415`,
		"the one after 3.881/4.136 with the bots' stage 3.742/4.177 over 2414",
		"the one after that 2.000/2.019 with the bots' stage 0.000/0.000 over 2410",
		"later 2.007/2.007 with the bots' stage 0.000/0.000 over 1",
		"2415 rounds in by the next Heartbeat, 0 later",
		"0 Heartbeats not read",
	}

	local ticks: { string } = {
		`{label} Tread tick stages a tick, {SUMMED}, ms p50/p95/p99 12.687/14.028/14.715`,
		"2415 ticks",
		"antiEsp p95 ms beside them, p50/p95/p99 over the reads 2.008/2.013/2.014",
		"the finish alone ms p50/p95/p99 1.883/2.130/2.232 over 2415 held ticks",
		"0 rounds dropped",
	}

	local counts: { string } = {
		`{label} counts, p50/p95/p99 over the reads: recordsSent a relay run 1427.100/1516.750/1528.350`,
		"recordsCut a relay run 0.000/0.000/0.000",
		"bytesOut a relay run 20782.850/21647.750/21730.650",
		"antiEspTests a tick 331.950/358.350/362.650",
	}

	local group: { string } = {
		`{label} group spread: 149 bots`,
		"449845 OwnerStates heard",
		"450063 Moves sent",
		"0 lost",
		"0 held",
		"moved 160.62 studs on average",
		"fastest 10.01 studs/s",
		"0 holds",
		"the body moving 0.00 studs at most in one",
		`reports \{"standIn":229,"gap":149}`,
	}

	local lines: { string } = {
		table.concat(calibration, SEPARATOR),
		table.concat(start, COMMA),
		`{label} mode: 4 relay workers started, on for this load; views 1 in process, 38/37/37/37 on the workers`,
		table.concat(server, SEPARATOR),
		table.concat(heartbeats, SEPARATOR),
		table.concat(ticks, SEPARATOR),
		table.concat(counts, SEPARATOR),
		`{label} real player: 12.34 studs from the load's point as the window opened, 456.78 walked in it`,
	}

	local summary: { string } = table.clone(SUMMARY)
	if clocks then
		local parts: { string } = {}
		for _, name: string in clocks do
			table.insert(parts, `{name} {CLOCK}`)
			table.insert(summary, `clock {name}Ms {CLOCK}`)
		end

		local head: string = `{label} relay clocks, ms p50/p95/p99 over the reads, {ACROSS}`
		table.insert(lines, `{head}: {table.concat(parts, SEPARATOR)}`)
	end

	table.sort(summary)
	table.insert(lines, table.concat(group, COMMA))
	table.insert(lines, `{label} summary over 49 reads, p50/p95/p99: {table.concat(summary, SEPARATOR)}`)

	return lines
end

--[[
    A half's figures at the size the live half's lines give them, with a
    live step 1 half's OwnerState sends and checks, step 2's, step 3's and
    the near rechecks' at the most digits a 150-player half could print, and
    each relay clock named at its p50 and p95 when clocks are given
--]]

function Report.figures(clocks: { string }?): { [string]: number }
	local figures: { [string]: number } = {
		calibration = 13.31,
		playerFrom = 12.34,
		playerMoved = 456.78,
		heartbeats = 59.97,
		fps = 53.24,
		frameP50 = 16.68,
		frameP95 = 19.44,
		treadP50 = 12.825,
		treadP95 = 14.129,
		botsP50 = 0,
		botsP95 = 0,
		place1P50 = 12.825, -- As the live half's line by place gives each of its first three places
		place1P95 = 14.129,
		place2P50 = 3.881,
		place2P95 = 4.136,
		place3P50 = 2.000,
		place3P95 = 2.019,
		tickFrameP50 = 16.712,
		tickFrameP95 = 19.876,
		tickP50 = 12.687,
		tickP95 = 14.028,
		decode = 1.328,
		simulate = 4.781,
		npcs = 0.049,
		history = 0.346,
		relay = 4.325,
		finish = 1.883,
		relaySend = 116.667, -- Milliseconds, a slow server's frames of about 100 ms each
		antiEsp = 2.008,
		antiEspTests = 331.95,
		antiEspRays = 10441.2,
		antiEspHidden = 43120,
		antiEspNearRechecks = 447000, -- All 22,350 pairs of 150 players near, hidden and rechecked each tick at 20 Hz
		antiEspNearGap = 150, -- Milliseconds: an ask past failOpen's 150 ms fails the pair open, ending its rechecks
		antiEspFailOpens = 0,
		antiEspWorkerTests = 1740000,
		antiEspWorkerBusy = 85.125,
		antiEspWorkerLongest = 6.75,
		antiEspLateBatches = 25,
		dropped = 0,
		relaySkipped = 0,
		deferred = 1000, -- Every tick of a 50 s window at 20 a second
		fallbacks = 1000,
		npcsWaited = 16000, -- Half of 32 awake NPCs every tick of the window, since none waits two ticks running
		antiEspCut = 3000, -- Every slice of a 50 s window at 60 Heartbeats a second
		relayLeft = 37000, -- A quarter of 150 viewers, rounded down, every relay run of the window
		relayOver = 1000,
		farHalved = 1000,
		records = 1427.1,
		recordsCut = 0,
		crowdRest = 17550, -- Pairs past a 32-player cap: 150 viewers, each with 117 of its 149 candidates past it
		bytes = 20782.85,
		viewerP50 = 2674,
		viewerP95 = 3052,
		ownerFull = 152400,
		ownerAcks = 152550,
		ownerChecked = 1017,
		ownerMismatches = 380,
		skipped = 14250,
	}

	for _, name: string in clocks or {} do
		figures[`clock {name} p50`] = 0.123
		figures[`clock {name} p95`] = 0.456
	end

	return figures
end

return Report
