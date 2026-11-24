--[[
    A Heartbeat that owes two ticks after calm ones, with the split on, runs
    both in today's shape with nothing deferred, the split stage on the
    later alone, and the calm count starts again from the tick after them
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local TWO_OWED: number = 1.5 -- The share that, after two quarters, owes two ticks at once

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	-- 1) Ticks 21 and 22 on one Heartbeat: the split stage skips 21 as a catch-up does and runs 22 whole, holding
	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, TWO_OWED)}`
	local expected: string =
		"poll 20, after 20, slices 20; slices 20; before 21, slices 21, after 21, before 22, split 22"
	if got ~= expected or Split.flags(loop) ~= Tick.TICKED + Tick.HELD then
		return false, `A Heartbeat owing two ticks after calm ones ran {got}, flagged {Split.flags(loop)}`
	end

	-- 2) Neither counts as calm, so the 20 calm ticks after them pass before the next defers
	got = Split.calm(loop, CALM_TICKS)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {CALM_TICKS} calm ticks of a catch-up Heartbeat: {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 42, after 42, slices 42; slices 42; before 43, slices 43, early 43" then
		return false, `The tick {CALM_TICKS} calm ticks after a catch-up Heartbeat ran {got}`
	end

	return true, nil
end
