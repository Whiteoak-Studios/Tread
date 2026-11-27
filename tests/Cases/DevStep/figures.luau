--[[
    A window's figures are the ones its lines carry, by the names the step
    table reads, Tread's on its heaviest place, a step half's tick frames
    and real player, each a row, none unsampled, and the calibration's loop
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Window = require("../../Fixtures/DevStep/Window")

local TOLERANCE: number = 1e-9 -- Past the rounding of milliseconds worked from seconds
local NAMES: { string } = { "before", "after" }

-- Each figure worked by hand from the window: by nearest rank, of two values p50 is the first and p95 the second,
-- and of four p50 is the second and p95 the fourth. The tick's own Heartbeat holds Tread's 3 and 5 ms, the
-- heaviest, with the bots' stage 1 ms in each, the one after 2 and 3 ms, and the one after that 1 and 0.5 ms. No
-- Heartbeat ran a deferred tick's rest. The ticks dropped, the relay runs skipped, the OwnerState checks compared and
-- missed, the NPC steps made to wait, the slices cut, the viewer turns left, the relay runs over the budget and with
-- the far band halved, and anti-ESP's hidden results, fail-opens, tests on workers and late batches are each summed
-- over both reads, the crowd cap's rest a relay run is its rate's p50, the send time is 0.02 s, the lower of 0.02 and
-- 0.0365, in milliseconds, and the longest batch's p95 of 0.002 and 0.004 s is 4 ms
local EXPECTED: { [string]: number } = {
	heartbeats = 64,
	fps = 50,
	frameP50 = 17,
	frameP95 = 20,
	treadP50 = 3,
	treadP95 = 5,
	botsP50 = 1,
	botsP95 = 1,
	place1P50 = 3,
	place1P95 = 5,
	place2P50 = 2,
	place2P95 = 3,
	place3P50 = 0.5,
	place3P95 = 1,
	deferred = 0,
	fallbacks = 0,
	relaySend = 20,
	npcsWaited = 10,
	antiEspCut = 3,
	relayLeft = 6,
	relayOver = 4,
	farHalved = 2,
	tickP50 = 4,
	tickP95 = 6,
	decode = 0.25,
	simulate = 1,
	npcs = 0,
	history = 0.125,
	relay = 1.5,
	finish = 1.5,
	antiEsp = 0.625,
	antiEspTests = 50,
	antiEspRays = 900,
	antiEspHidden = 40,
	antiEspFailOpens = 1,
	antiEspWorkerTests = 900,
	antiEspWorkerBusy = 12.5,
	antiEspWorkerLongest = 4,
	antiEspLateBatches = 2,
	dropped = 1,
	relaySkipped = 2,
	records = 100,
	recordsCut = 0,
	crowdRest = 1.5,
	bytes = 2000,
	viewerP50 = 1000,
	viewerP95 = 3000,
	ownerChecked = 78,
	ownerMismatches = 3,
	skipped = 120,
	["clock head p50"] = 0.25,
	["clock head p95"] = 0.5,
	["clock back p50"] = 1,
	["clock back p95"] = 2,
}

-- Whether two records hold the same names, each figure within the tolerance, or the first name that differs
local function differs(got: { [string]: number }, expected: { [string]: number }): string?
	for name: string, value: number in expected do
		local figure: number? = got[name]
		if figure == nil or math.abs(figure - value) > TOLERANCE then
			return `{name} read {figure}, not {value}`
		end
	end

	for name: string, figure: number in got do
		if expected[name] == nil then
			return `{name} read {figure}, which the window carries no samples for`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) Every figure the window's lines carry, and nothing else
	local figures: { [string]: number } = Run.figures(Window.taken())
	local problem: string? = differs(figures, EXPECTED)
	if problem then
		return false, `The window's figures: {problem}`
	end

	-- 2) Each a figure the step benchmark's table has a row for, below its head line, the other half missing so a
	-- quiet row at 0 still prints
	for name: string, value: number in figures do
		local alone: { [string]: number } = { [name] = value }
		local rows: { string } = string.split(Compare.table("S4", NAMES, alone, nil), "\n")
		if #rows ~= 2 then
			return false, `The table has {#rows - 1} rows for the window's figure {name}`
		end
	end

	-- 3) With the first Heartbeat after a tick's taking 9 ms, Tread's 3 and 9 ms there are the heaviest, with no bots
	local heavier: any = Window.taken()
	heavier.readout.times[2] = 0.009
	local moved: { [string]: number } = Run.figures(heavier)
	if
		math.abs(moved.treadP50 - 3) > TOLERANCE
		or math.abs(moved.treadP95 - 9) > TOLERANCE
		or moved.botsP50 ~= 0
		or moved.botsP95 ~= 0
	then
		return false, `With 9 ms after the tick's Heartbeat, Tread read {moved.treadP50}/{moved.treadP95} there`
	end

	-- 4) A step half's window adds its frames holding a tick, by nearest rank of three, and its real player, each a
	-- row of the table too
	local stepped: any = Window.taken()
	stepped.sampled.tickFrames = { 25, 17, 18 }
	stepped.walked = { from = 12.5, moved = 40.25 }
	local half: { [string]: number } = Run.figures(stepped)
	local added: { [string]: number } = table.clone(EXPECTED)
	added.tickFrameP50 = 18
	added.tickFrameP95 = 25
	added.playerFrom = 12.5
	added.playerMoved = 40.25

	problem = differs(half, added)
	if problem then
		return false, `A step half's figures: {problem}`
	end

	for _, name: string in { "tickFrameP50", "tickFrameP95", "playerFrom", "playerMoved" } do
		local alone: { [string]: number } = { [name] = half[name] }
		if #string.split(Compare.table("S4", NAMES, alone, nil), "\n") ~= 2 then
			return false, `The table has no row of its own for a step half's {name}`
		end
	end

	-- 5) A window that took nothing carries only the commands skipped
	local empty: any = {
		sampled = { frames = {}, heartbeatTimes = {}, physicsTimes = {}, dataSend = {} },
		elapsed = 0,
		readout = { times = {}, flags = {}, bots = {}, through = 0, lost = 0 },
		totals = {},
		finishes = {},
		roundsDropped = 0,
		samples = {},
		rates = {},
		skipped = 0,
	}

	problem = differs(Run.figures(empty), { skipped = 0 })
	if problem then
		return false, `An empty window's figures: {problem}`
	end

	-- 6) The calibration's loop p50 is the first figure its line gives, 13.31 µs of these three, and a refusal has none
	local Calibration: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Calibration)
	local measured: any = {
		loop = { 16.091, 13.31, 12.5 },
		casts = { 2.264, 3.102 },
		bytes = 1024,
		frames = 100,
		seconds = 1.637,
	}

	local loop: number? = Run.calibrated(Calibration.line(measured))
	if loop == nil or math.abs(loop - 13.31) > TOLERANCE then
		return false, `The calibration line {Calibration.line(measured)} gave the loop {loop}`
	elseif Run.calibrated("the calibration stopped: a Blockcast missed the part it was cast at") ~= nil then
		return false, "A calibration that stopped gave a loop"
	end

	return true, nil
end
