--[[
    Ticks 3, 3, 2 or 3, 2 Heartbeats apart never defer, ticks 3 apart defer
    from the fourth, and an early tick costs 3 whole ticks after a whole one
    and 4 after a deferred one, whose release it runs inside
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local AFTER_WHOLE: number = 3 -- The whole ticks an early tick after a whole one costs, itself among them
local AFTER_DEFERRED: number = 4 -- The whole ticks an early tick after a deferred one costs, itself among them
local CYCLES: number = 10 -- The times each pattern of gaps runs on its own loop
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local THREE_QUARTERS: number = 0.75 -- The share that begins a tick a Heartbeat early, 2 after the one before

-- The Heartbeats from each tick to the next, repeated: 53.3 Heartbeats a second, then 50
local PATTERNS: { { number } } = { { 3, 3, 2 }, { 3, 2 } }

-- Each gap's Heartbeats' shares of a tick, the tick beginning in the last, that many Heartbeats after the tick before
local GAPS: { [number]: { number } } = {
	[2] = { QUARTER, THREE_QUARTERS },
	[3] = { QUARTER, QUARTER, HALF },
}

-- Runs a pattern of gaps cycles times on a new loop with the split on, giving every run it made in order
local function pattern(gaps: { number }, cycles: number): string
	local loop: Split.Loop = Split.new()
	loop.Tick.useSplit(true)

	local got: { string } = {}
	for _ = 1, cycles do
		for _, gap: number in gaps do
			for _, share: number in GAPS[gap] do
				table.insert(got, Split.beat(loop, share))
			end
		end
	end

	return table.concat(got, ", ")
end

return function (): (boolean, string | nil)
	-- 1) A gap of 2 sets the count back to 0 and a pattern has at most two gaps of 3 between, so every tick runs whole
	for _, gaps: { number } in PATTERNS do
		local got: string = pattern(gaps, CYCLES)
		local last: number = #gaps * CYCLES
		local named: string = table.concat(gaps, ", ")
		if string.find(got, "early", 1, true) then
			return false, `A tick deferred with ticks {named} Heartbeats apart: {got}`
		elseif not string.find(got, `before {last}, slices {last}, split {last}`, 1, true) then
			return false, `With ticks {named} Heartbeats apart, tick {last} did not run whole: {got}`
		end
	end

	-- 2) Ticks 3 apart: the first three run whole, counting 0, 1 and 2, and the fourth defers
	local loop: Split.Loop = Split.new()
	loop.Tick.useSplit(true)

	local got: string = Split.calm(loop, CALM_TICKS)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred in the first {CALM_TICKS} ticks 3 Heartbeats apart: {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 3, after 3, slices 3; slices 3; before 4, slices 4, early 4" then
		return false, `The fourth tick 3 Heartbeats apart ran {got}`
	end

	-- 3) A tick 2 Heartbeats after a deferred one runs inside the rest's release, so it is not alone and the tick after
	-- it counts 0: it and the 3 calm ticks after it run whole, and the next defers
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, THREE_QUARTERS)}`
	if got ~= "slices 4, split 4; poll 4, after 4, before 5, slices 5, split 5" then
		return false, `The tick 2 Heartbeats after a deferred one ran {got}`
	end

	got = Split.calm(loop, AFTER_DEFERRED - 1)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {AFTER_DEFERRED} whole ticks of an early one after a deferred one: {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 8, after 8, slices 8; slices 8; before 9, slices 9, early 9" then
		return false, `The tick after an early one's {AFTER_DEFERRED} whole ticks ran {got}`
	end

	-- 4) Tick 10 comes early after deferred tick 9, so tick 11 runs whole; tick 12, 2 Heartbeats after it, runs alone
	-- and counts 0: it and the 2 calm ticks after it run whole, and the next defers
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, THREE_QUARTERS)}`
	if got ~= "slices 9, split 9; poll 9, after 9, before 10, slices 10, split 10" then
		return false, `The tick 2 Heartbeats after deferred tick 9 ran {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 10, after 10, slices 10; slices 10; before 11, slices 11, split 11" then
		return false, `The calm tick after an early one ran {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, THREE_QUARTERS)}`
	if got ~= "poll 11, after 11, slices 11; before 12, slices 12, split 12" then
		return false, `The tick 2 Heartbeats after a whole one ran {got}`
	end

	got = Split.calm(loop, AFTER_WHOLE - 1)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {AFTER_WHOLE} whole ticks of an early one after a whole one: {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 14, after 14, slices 14; slices 14; before 15, slices 15, early 15" then
		return false, `The tick after an early one's {AFTER_WHOLE} whole ticks ran {got}`
	end

	return true, nil
end
