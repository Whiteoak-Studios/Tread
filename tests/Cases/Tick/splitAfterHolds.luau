--[[
    A stage after the split stage that holds in a deferred rest holds the
    tick as any stage does, its poll ending it, while the guard reads the
    split stage's own last hold alone, so the next tick runs whole
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 20, after 20, slices 20; slices 20; before 21, slices 21, early 21" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 1) In the rest, the split stage holds nothing and the stage after it holds the tick
	loop.holds = false
	loop.faults["after 21"] = "holds"
	got = Split.beat(loop, QUARTER)
	if got ~= "slices 21, split 21, after 21" or Split.flags(loop) ~= Tick.DEFERRED + Tick.HELD then
		return false, `A rest whose later stage held ran {got}, flagged {Split.flags(loop)}`
	elseif not Tick.holding() then
		return false, "Tick.holding answered false while a rest's later stage held the tick"
	end

	-- 2) Its poll ends the hold at the next Heartbeat, and the slice runs after it
	got = Split.beat(loop, QUARTER)
	if got ~= "poll after 21, slices 21" or Split.flags(loop) ~= Tick.POLLED + Tick.RELEASED or Tick.holding() then
		return false, `The later stage's poll ran {got}, flagged {Split.flags(loop)}`
	end

	-- 3) The split stage's own last run held nothing, so the next tick runs whole
	loop.holds = true
	got = Split.beat(loop, HALF)
	if got ~= "before 22, slices 22, split 22" then
		return false, `After a rest whose split stage held nothing, the next tick ran {got}`
	end

	return true, nil
end
