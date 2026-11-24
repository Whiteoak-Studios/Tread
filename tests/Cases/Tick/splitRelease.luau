--[[
    A tick owed at a release runs inside it whole, in today's shape, even
    when the ticks before it were calm and the split is on, and the calm
    count starts again after it
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local EIGHTH: number = 0.125 -- A share small enough that the Heartbeat after it still owes no tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 20, after 20, slices 20; slices 20; before 21, slices 21, early 21" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 1) The deferred rest holds, and its poll answers false while tick 22's time comes due
	loop.answer = false
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 21, split 21; poll 21; poll 21" then
		return false, `A deferred rest whose poll answered false ran {got}`
	end

	-- 2) The release, 4 Heartbeats after tick 21's, runs tick 22 whole inside it, its early part never run
	loop.answer = true
	got = Split.beat(loop, QUARTER)
	local flags: number = Tick.POLLED + Tick.RELEASED + Tick.TICKED + Tick.HELD
	if got ~= "poll 21, after 21, before 22, slices 22, split 22" or Split.flags(loop) ~= flags then
		return false, `A release that owed a tick ran {got}, flagged {Split.flags(loop)}`
	end

	-- 3) Tick 22 ran inside a release, so it is no calm tick: tick 23, 3 Heartbeats after it, where the gap alone would
	-- count it, still runs whole
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, EIGHTH)}; {Split.beat(loop, QUARTER)}`
	if got ~= "poll 22, after 22, slices 22; slices 22; before 23, slices 23, split 23" then
		return false, `The tick 3 Heartbeats after one run inside a release ran {got}`
	end

	return true, nil
end
