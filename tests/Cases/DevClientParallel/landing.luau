--[[
    A landing arm's clause counts each callback as in before the next of
    each frame event only when none of it fired between its two reads, with
    the synchronize waits read by nearest rank, and an arm of none reads 0
--]]

--!strict
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local EVENT: string = "PreSimulation"
local EVENTS: number = 3
local SPIN: number = 0.00025 -- Seconds each callback holds before it synchronizes
local APART: number = 0.01 -- Seconds between one callback's start and the next one's

-- Seconds each of the five callbacks waits from its synchronize to its resume, and how many of each frame event fired
-- between its two reads, in EVENTS' order: PreRender none, PreAnimation once in the last, PreSimulation once or twice in
-- three, and PostSimulation once in every one
local WAITS: { number } = { 0.004, 0.001, 0.005, 0.002, 0.003 }
local FIRED: { { number } } = {
	{ 0, 0, 0, 1 },
	{ 0, 0, 1, 1 },
	{ 0, 0, 1, 1 },
	{ 0, 0, 2, 1 },
	{ 0, 1, 0, 1 },
}

local FIRST_WORKER: number = 3 -- Of the callbacks, the first worker's, the second worker's after them
local BEFORE: { number } = { 10, 20, 30, 40 } -- Each event's count as the first callback read it before it synchronized

-- Waits of 1 to 5 ms read p50 3 and p95 5 by nearest rank, and of the five callbacks 5, 4, 2 and 0 saw none fire
local LINE: string =
	"PreSimulation arm: 5 callbacks over 3 events, synchronize wait p50 3.000 p95 5.000 ms, synchronized before the next PreRender 100.0%, PreAnimation 80.0%, PreSimulation 40.0%, PostSimulation 0.0%"

local EMPTY: string =
	"PreRender arm: 0 callbacks over 0 events, synchronize wait p50 0.000 p95 0.000 ms, synchronized before the next PreRender 0.0%, PreAnimation 0.0%, PreSimulation 0.0%, PostSimulation 0.0%"

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local layout: any = mounted.Work.LANDING
	local names: { string } = mounted.Work.EVENTS

	-- Each callback's sample in its worker's list, written by the layout, its counts moving on a frame a callback
	local workers: { { number } } = { {}, {} }
	for index: number, wait: number in WAITS do
		local list: { number } = workers[index <= FIRST_WORKER and 1 or 2]
		local at: number = #list
		local start: number = index * APART

		list[at + layout.START] = start
		list[at + layout.SPUN] = start + SPIN
		list[at + layout.SYNCED] = start + SPIN + wait

		for offset: number = 1, #names do
			local before: number = BEFORE[offset] + index
			list[at + layout.BEFORE + offset - 1] = before
			list[at + layout.AFTER + offset - 1] = before + FIRED[index][offset]
		end
	end

	local line: string = mounted.Lines.landing(EVENT, workers, EVENTS)
	if line ~= LINE then
		return false, `The arm's clause was "{line}", not "{LINE}"`
	end

	local empty: string = mounted.Lines.landing("PreRender", { {}, {} }, 0)
	if empty ~= EMPTY then
		return false, `An arm of no callbacks gave "{empty}", not "{EMPTY}"`
	end

	return true, nil
end
