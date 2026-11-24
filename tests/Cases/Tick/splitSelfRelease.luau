--[[
    A split stage that holds and releases inside its own run leaves the
    tick unheld as it returns, so the stages after it go straight on and
    the next tick runs whole, since only a hold still in place counts
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

	-- 1) The rest holds and releases itself: the stage after it runs beside it and nothing is left held
	loop.faults["split 21"] = "releases"
	got = Split.beat(loop, QUARTER)
	if got ~= "slices 21, split 21, after 21" or Split.flags(loop) ~= Tick.DEFERRED + Tick.RELEASED then
		return false, `A rest that released its own hold ran {got}, flagged {Split.flags(loop)}`
	elseif Tick.holding() then
		return false, "Tick.holding answered true after a rest released its own hold"
	end

	-- 2) The next tick runs whole, its split stage holding as ever
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 21; before 22, slices 22, split 22" or Split.flags(loop) ~= Tick.TICKED + Tick.HELD then
		return false, `After a rest that released its own hold, the next tick ran {got}, flagged {Split.flags(loop)}`
	end

	return true, nil
end
