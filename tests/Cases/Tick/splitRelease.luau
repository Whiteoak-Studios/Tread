--[[
    A tick owed at a release runs inside it whole, in today's shape, even
    when the ticks before it were calm and the split is on, and the calm
    count starts again after it
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local EIGHTH: number = 0.125 -- A share small enough that the Heartbeat after it still owes no tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 3, after 3, slices 3; slices 3; before 4, slices 4, early 4" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 1) The deferred rest holds, and its poll answers false while tick 5's time comes due
	loop.answer = false
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 4, split 4; poll 4; poll 4" then
		return false, `A deferred rest whose poll answered false ran {got}`
	end

	-- 2) The release, 4 Heartbeats after tick 4's, runs tick 5 whole inside it, its early part never run
	loop.answer = true
	got = Split.beat(loop, QUARTER)
	local flags: number = Tick.POLLED + Tick.RELEASED + Tick.TICKED + Tick.HELD
	if got ~= "poll 4, after 4, before 5, slices 5, split 5" or Split.flags(loop) ~= flags then
		return false, `A release that owed a tick ran {got}, flagged {Split.flags(loop)}`
	end

	-- 3) Tick 5 ran inside a release, so it is no calm tick: tick 6, 3 Heartbeats after it, where the gap alone would
	-- count it, still runs whole
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, EIGHTH)}; {Split.beat(loop, QUARTER)}`
	if got ~= "poll 5, after 5, slices 5; slices 5; before 6, slices 6, split 6" then
		return false, `The tick 3 Heartbeats after one run inside a release ran {got}`
	end

	return true, nil
end
