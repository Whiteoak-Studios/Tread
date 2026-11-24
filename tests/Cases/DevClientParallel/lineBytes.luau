--[[
    Each probe's line at its widest stays whole within what the dev scope's
    clientCost carries, for the dev client's own counts and arms, and a line
    past it is cut to it
--]]

--!strict
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local LINE_BYTES: number = 2048 -- clientCost's line, string(1..2048) in dev/Schemas/Dev.volt
local PLAYER: string = string.rep("M", 20) -- The longest name Roblox gives a player
local SLOTS: number = 4096 -- Tread's character slots, past which no rig is drawn
local PASSES: number = 99999999 -- Eight digits of passes, far past a loop sized to 2 ms

-- Every time under a 60 s window prints at most five whole digits of milliseconds, a count at most five digits, and a
-- parallelism at most two digits for the counts measured
local LONGEST: number = 59.999999 -- Seconds
local MOST: number = 99999
local PARALLELISM: number = 99.99

-- The landing callbacks as their widest count, four digits, since an arm counts at most its frames on each worker
local CALLBACKS: number = 9999

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local Lines: any = mounted.Lines
	local layout: any = mounted.Work.LANDING
	local names: { string } = mounted.Work.EVENTS
	local parallel: any = mounted.config.parallel

	-- 1) P6: each count at its widest, threads at its workers since every wall is the same, then each landing arm's
	-- callbacks every one waiting its longest and resuming before every next event
	local counts: { any } = {}
	for _, workers: number in parallel.cores.workers do
		table.insert(counts, {
			workers = workers,
			repeats = parallel.cores.repeats,
			batches = parallel.cores.repeats,
			wall = LONGEST,
			wallHigh = LONGEST,
			start = LONGEST,
			busy = LONGEST,
			parallelism = PARALLELISM,
			byNext = parallel.cores.repeats,
			early = parallel.cores.repeats,
		})
	end

	local samples: { number } = {}
	for callback: number = 0, CALLBACKS - 1 do
		local at: number = callback * layout.STRIDE
		samples[at + layout.START] = 0
		samples[at + layout.SPUN] = 0
		samples[at + layout.SYNCED] = LONGEST

		for offset: number = 1, #names do
			samples[at + layout.BEFORE + offset - 1] = MOST
			samples[at + layout.AFTER + offset - 1] = MOST
		end
	end

	local cores: { string } = { Lines.counts({ LONGEST }, PASSES, counts) }
	for _, event: string in parallel.landing.events do
		table.insert(cores, Lines.landing(event, { samples }, MOST))
	end

	-- 2) P8: the off arm at its widest, and each arm with the widest negative added time, its steps' figures at their
	-- widest, and its foot reads split three ways, whose shares print widest
	local function widest(workers: number, spans: { number }): any
		local lags: { number } = {}
		for read: number = 1, MOST do
			table.insert(lags, read % 3)
		end

		return {
			workers = workers,
			spans = spans,
			computes = table.create(MOST, LONGEST),
			writes = table.create(MOST, LONGEST),
			walls = table.create(MOST, LONGEST),
			callbacks = MOST,
			inStep = MOST,
			early = MOST,
			lags = lags,
		}
	end

	local off: any = widest(0, table.create(MOST, LONGEST))
	local arms: { any } = { widest(0, { 0 }) }
	for _, workers: number in parallel.bend.workers do
		table.insert(arms, widest(workers, { 0 }))
	end

	-- The line cuts anything past the bytes, so a widest line that fits is one that still ends with its last clause
	local probes: { [string]: { string } } = {
		P6 = cores,
		P8 = { Lines.bend(SLOTS, off, arms) },
	}

	for probe: string, clauses: { string } in probes do
		local line: string = Lines.line(PLAYER, clauses, nil)
		local last: string = clauses[#clauses]

		if #line > LINE_BYTES or string.sub(line, -#last) ~= last then
			return false, `{probe}'s widest line was cut at {#line} B, past what clientCost's {LINE_BYTES} B carries`
		end
	end

	-- 3) A line past the bytes, as a failure's text may make it, is cut to them
	local cut: string = Lines.line(PLAYER, cores, string.rep("x", LINE_BYTES))
	if #cut ~= LINE_BYTES then
		return false, `A line past {LINE_BYTES} B was cut to {#cut} B`
	end

	return true, nil
end
