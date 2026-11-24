--[[
    A tick defers only once the 20 before it were calm, each run alone with
    the next 3 Heartbeats or more after it: a tick 2 Heartbeats after the
    one before sets the count back to 0, and deferred ticks stay calm
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before a tick that defers
local BEFORE_GAP: number = 10 -- The calm ticks run before the short gap
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
	if got ~= "poll 10, after 10, slices 10; before 11, slices 11, split 11" then
		return false, `The tick 2 Heartbeats after the one before ran {got}`
	end

	-- 2) So the 19 calm ticks after it count 1 to 19 and none defers
	got = Split.calm(loop, CALM_TICKS - 1)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {CALM_TICKS - 1} calm ticks of the short gap: {got}`
	end

	-- 3) And the twentieth after the gap's tick defers
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 30, after 30, slices 30; slices 30; before 31, slices 31, early 31" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 4) A deferred tick's next is 3 Heartbeats on, so each tick after it is calm and defers too
	got = Split.calm(loop, 2)
	local expected: string = "slices 31, split 31, poll 31, after 31, slices 31, before 32, slices 32, early 32, "
		.. "slices 32, split 32, poll 32, after 32, slices 32, before 33, slices 33, early 33"
	if got ~= expected then
		return false, `The two calm ticks after a deferred one ran {got}`
	end

	return true, nil
end
