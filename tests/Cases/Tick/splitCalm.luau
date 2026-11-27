--[[
    A tick defers only once the 3 before it were calm, each run alone with
    the next 3 Heartbeats or more after it: a tick 2 Heartbeats after the
    one before sets the count back to 0, and deferred ticks stay calm
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local BEFORE_GAP: number = 3 -- The calm ticks before the short gap, after which a tick 3 Heartbeats on would defer
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local THREE_QUARTERS: number = 0.75 -- The share that begins a tick a Heartbeat early, 2 after the one before

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	loop.Tick.useSplit(true)

	local got: string = Split.calm(loop, BEFORE_GAP)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred in the first {BEFORE_GAP} calm ticks: {got}`
	end

	-- 1) A tick run alone 2 Heartbeats after the one before runs whole and sets the count back to 0
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, THREE_QUARTERS)}`
	if got ~= "poll 3, after 3, slices 3; before 4, slices 4, split 4" then
		return false, `The tick 2 Heartbeats after the one before ran {got}`
	end

	-- 2) So the 2 calm ticks after it count 1 and 2 and none defers
	got = Split.calm(loop, CALM_TICKS - 1)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {CALM_TICKS - 1} calm ticks of the short gap: {got}`
	end

	-- 3) And the third after the gap's tick defers
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 6, after 6, slices 6; slices 6; before 7, slices 7, early 7" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 4) A deferred tick's next is 3 Heartbeats on, so each tick after it is calm and defers too
	got = Split.calm(loop, 2)
	local expected: string = "slices 7, split 7, poll 7, after 7, slices 7, before 8, slices 8, early 8, "
		.. "slices 8, split 8, poll 8, after 8, slices 8, before 9, slices 9, early 9"
	if got ~= expected then
		return false, `The two calm ticks after a deferred one ran {got}`
	end

	return true, nil
end
