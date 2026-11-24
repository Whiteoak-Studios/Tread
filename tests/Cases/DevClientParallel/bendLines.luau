--[[
    P8's arms give their figures step by step: each arm's added time over
    the off arm's p50, the solves, writes and wall of each step every worker
    reached summed across them, the writes in their step, the early starts
    and the foot's lags, as the clause prints them
--]]

--!strict
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local RIGS: number = 149
local APART: number = 0.01 -- Seconds between one step's PreSimulation and the next one's
local MS: number = 0.001 -- A millisecond in seconds, which the stamps below are counted in
local SOLVE: number = 0.5 * MS -- Each callback's solve
local RESUME: number = 0.2 * MS -- From each callback's solve to its resume once synchronized

-- Each arm's spans by step, and the steps the main thread stamped only the PreSimulation of
local OFF_SPANS: { number } = { 1 * MS, 1 * MS, 2 * MS, 1 * MS }
local SERIAL_SPANS: { number } = { 1.5 * MS, 2.5 * MS }
local WORKER_SPANS: { number } = { 4 * MS, 3 * MS, 5 * MS }

-- The two workers' writes by step, which sum to 10, 4 and 10 ms a step while each worker's own p50 is 2 ms, and the
-- second worker starting step 3 early and writing step 2 after its PostSimulation
local WRITES: { { number } } = { { 1 * MS, 2 * MS, 9 * MS }, { 9 * MS, 2 * MS, 1 * MS } }
local LATE: { [number]: { [number]: boolean } } = { [2] = { [2] = true } }
local EARLY: { [number]: { [number]: boolean } } = { [2] = { [3] = true } }
local AHEAD: number = 0.1 * MS -- How long after the PreSimulation stamp a callback starts, and how long before for an early one

-- Every stamped step's span, solves of 0.5 ms twice, the 10 ms p50 of 10, 4 and 10, walls of 9.7, 2.7 and 9.9 ms,
-- one late of six and one early, and the feet's lags
local LINE: string = table.concat({
	"P8 over 149 stand-ins, every leg bent each step, times a step summed over its workers",
	"off span p50 1.000 p95 2.000 ms over 4 steps",
	"serial added p50 0.500 p95 1.500 ms, compute p50 0.500 ms, writes p50 0.200 ms, wall p50 0.700 ms over 2 steps, in step 100.0% of 2, 0 early, foot lag 0/1/2+ steps 100.0%/0.0%/0.0% of 2 reads",
	"2 workers added p50 3.000 p95 4.000 ms, compute p50 1.000 ms, writes p50 10.000 ms, wall p50 9.700 ms over 3 steps, in step 83.3% of 6, 1 early, foot lag 0/1/2+ steps 60.0%/20.0%/20.0% of 5 reads",
}, "; ")

-- The main thread's stamps for the spans, a step apiece from step 1, with one more PreSimulation it never closed
local function stamps(spans: { number }): ({ [number]: number }, { [number]: number })
	local pres: { [number]: number } = {}
	local posts: { [number]: number } = {}
	for step: number, span: number in spans do
		pres[step] = step * APART
		posts[step] = step * APART + span
	end

	pres[#spans + 1] = (#spans + 1) * APART

	return pres, posts
end

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local Lines: any = mounted.Lines
	local layout: any = mounted.Work.BENDING

	-- One callback's sample in a worker's list, by the layout
	local function sample(list: { number }, step: number, start: number, resumed: number, wrote: number, late: boolean)
		local at: number = #list
		local before: number = step - 1
		local after: number = before
		if late then
			after += 1
		end

		list[at + layout.STEP] = step
		list[at + layout.START] = start
		list[at + layout.SOLVED] = start + SOLVE
		list[at + layout.SYNCED] = resumed
		list[at + layout.WRITTEN] = resumed + wrote
		list[at + layout.BEFORE] = before
		list[at + layout.AFTER] = after
	end

	-- 1) The off arm: its spans alone, the step it never closed left out
	local offPres: { [number]: number }, offPosts: { [number]: number } = stamps(OFF_SPANS)
	local off: any = Lines.arm(0, offPres, offPosts, {}, {})

	-- 2) The serial arm: the main thread's own samples, resumed as it solved, with a write of 0.2 ms each step
	local serialPres: { [number]: number }, serialPosts: { [number]: number } = stamps(SERIAL_SPANS)
	local own: { number } = {}
	for step: number = 1, #SERIAL_SPANS do
		local start: number = serialPres[step]
		sample(own, step, start, start + SOLVE, RESUME, false)
	end

	local serial: any = Lines.arm(0, serialPres, serialPosts, { own }, { 0, 0 })

	-- 3) Two workers over three stamped steps, each also handing in a step 4 the main thread never stamped
	local workerPres: { [number]: number }, workerPosts: { [number]: number } = stamps(WORKER_SPANS)
	local lists: { { number } } = { {}, {} }
	for worker: number, list: { number } in lists do
		for step: number = 1, #WORKER_SPANS + 1 do
			local early: boolean = EARLY[worker] ~= nil and EARLY[worker][step] == true
			local late: boolean = LATE[worker] ~= nil and LATE[worker][step] == true
			local start: number = step * APART + AHEAD
			if early then
				start = step * APART - AHEAD
			end

			local wrote: number = WRITES[worker][step] or RESUME
			sample(list, step, start, start + SOLVE + RESUME, wrote, late)
		end
	end

	local workers: any = Lines.arm(2, workerPres, workerPosts, lists, { 0, 0, 1, 3, 0 })

	-- 4) The clause
	local line: string = Lines.bend(RIGS, off, { serial, workers })
	if line ~= LINE then
		return false, `The arms printed "{line}", not "{LINE}"`
	end

	return true, nil
end
