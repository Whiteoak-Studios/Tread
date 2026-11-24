--[[
    A deferred tick runs to its split stage's early part on its Heartbeat,
    the slice and then the parked rest on the next and the finish after; a
    throw in either part is reported and stops nothing after it
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before the first that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)
	Split.beat(loop, QUARTER)
	Split.beat(loop, QUARTER)

	-- 1) The tick's Heartbeat runs to the early part, the next the slice and then the rest, and the one after the finish
	local got: string = Split.beat(loop, HALF)
	if got ~= "before 21, slices 21, early 21" or Split.flags(loop) ~= Tick.TICKED or not Tick.holding() then
		return false, `The deferring tick's Heartbeat ran {got}, flagged {Split.flags(loop)}`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "slices 21, split 21" or Split.flags(loop) ~= Tick.DEFERRED + Tick.HELD or not Tick.holding() then
		return false, `The Heartbeat after it ran {got}, flagged {Split.flags(loop)}`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "poll 21, after 21, slices 21" or Split.flags(loop) ~= Tick.POLLED + Tick.RELEASED or Tick.holding() then
		return false, `The rest's finish ran {got}, flagged {Split.flags(loop)}`
	end

	-- 2) An early part that throws is reported as its stage, warned as an early part whose run still follows, and its
	-- rest still runs at the next Heartbeat
	loop.faults["early 22"] = "throws"
	got = Split.beat(loop, HALF)
	if got ~= "before 22, slices 22, early 22" or table.concat(loop.reports, ", ") ~= "stage split" then
		return false, `A tick whose early part threw ran {got}, reported {table.concat(loop.reports, ", ")}`
	end

	local warned: string = loop.warns[1] or ""
	local early: string = "The split stage's early part threw, losing the rest of that part, and its run still follows"
	if #loop.warns ~= 1 or string.sub(warned, 1, #early) ~= early then
		return false, `An early part that threw was warned {#loop.warns} times, first as: {warned}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}`
	if got ~= "slices 22, split 22; poll 22, after 22, slices 22" then
		return false, `After an early part threw, the next two Heartbeats ran {got}`
	end

	-- 3) A rest that throws before holding is reported, the stages after it run beside it, and with no hold kept the
	-- next tick runs whole
	loop.faults["split 23"] = "throws"
	got = Split.beat(loop, HALF)
	if got ~= "before 23, slices 23, early 23" then
		return false, `The tick whose rest throws ran {got} on its Heartbeat`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "slices 23, split 23, after 23" or Split.flags(loop) ~= Tick.DEFERRED or Tick.holding() then
		return false, `A rest that threw before holding ran {got}, flagged {Split.flags(loop)}`
	elseif table.concat(loop.reports, ", ") ~= "stage split, stage split" then
		return false, `A rest that threw left the reports {table.concat(loop.reports, ", ")}`
	end

	-- A rest's throw is a stage's own, its work for the tick dropped
	warned = loop.warns[2] or ""
	local dropped: string = "The split stage threw, and its work was dropped for the tick"
	if #loop.warns ~= 2 or string.sub(warned, 1, #dropped) ~= dropped then
		return false, `A rest that threw was warned as: {warned}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 23; before 24, slices 24, split 24" then
		return false, `After a rest that held nothing, the next tick's Heartbeats ran {got}`
	end

	-- 4) An early part may not hold the tick: the hold is refused naming its stage and the waiting rest, and the tick
	-- goes on deferred
	loop.faults["early 25"] = "holds"
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	local refused: string = "Tick.hold came from the split stage while a deferred tick's rest waits"
	if got ~= "poll 24, after 24, slices 24; slices 24; before 25, slices 25, early 25" then
		return false, `The tick whose early part tried to hold ran {got}`
	elseif not string.find(loop.refusal or "", refused, 1, true) then
		return false, `An early part's hold was not refused naming it and the waiting rest: {loop.refusal}`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "slices 25, split 25" or Split.flags(loop) ~= Tick.DEFERRED + Tick.HELD then
		return false, `After the refused hold, the rest ran {got}, flagged {Split.flags(loop)}`
	elseif #loop.reports ~= 2 then
		return false, `A refused hold left {#loop.reports} reports, not the 2 before it`
	end

	return true, nil
end
