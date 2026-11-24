--[[
    On a deferred rest's Heartbeat the between stages run while the rest
    still waits, so one that tries to hold there is refused naming it and
    the rest runs from its own stage, while elsewhere one still may hold
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

	-- 1) The slice tries to hold before the rest: refused naming it, with nothing reported, and the rest runs its own
	-- stage, which holds
	loop.faults["slices 21"] = "holds"
	got = Split.beat(loop, QUARTER)
	loop.faults["slices 21"] = nil

	local refused: string = "Tick.hold came from the slices stage while a deferred tick's rest waits"
	if got ~= "slices 21, split 21" or Split.flags(loop) ~= Tick.DEFERRED + Tick.HELD then
		return false, `A rest's Heartbeat whose slice tried to hold ran {got}, flagged {Split.flags(loop)}`
	elseif not string.find(loop.refusal or "", refused, 1, true) then
		return false, `The slice's hold before a waiting rest was not refused naming it: {loop.refusal}`
	elseif #loop.reports ~= 0 then
		return false, `A refused hold gave the reports {table.concat(loop.reports, ", ")}`
	end

	-- 2) With no rest waiting, the slice still may hold, as before the split
	loop.refusal = nil
	loop.faults["slices 21"] = "holds"
	got = Split.beat(loop, QUARTER)
	loop.faults["slices 21"] = nil

	if got ~= "poll 21, after 21, slices 21" or not Tick.holding() or loop.refusal ~= nil then
		return false, `A slice that held after the rest's release ran {got}, refused {loop.refusal}`
	end

	got = Split.beat(loop, HALF)
	if got ~= "poll slices 21, before 22, slices 22, split 22" then
		return false, `The slice's hold ended with tick 22 owed, and ran {got}`
	end

	return true, nil
end
