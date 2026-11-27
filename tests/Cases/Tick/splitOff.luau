--[[
    With the split off, as it starts, no early part runs and every tick
    runs whole, calm or not; turned on, the next calm tick defers, and
    turned off while a rest waits, that rest still runs at the next Heartbeat
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers while the split is on
local OFF_TICKS: number = CALM_TICKS * 2 -- The calm ticks run while it is off, twice the count
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick

	if Tick.splitOn() then
		return false, "The split was on from start"
	end

	-- 1) Off, no tick defers however calm, and each holds on its Heartbeat and finishes on the next
	local got: string = Split.calm(loop, OFF_TICKS)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred over {OFF_TICKS} calm ticks with the split off: {got}`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "poll 6, after 6, slices 6" or Split.flags(loop) ~= Tick.POLLED + Tick.RELEASED then
		return false, `With the split off, a held tick's next Heartbeat ran {got}, flagged {Split.flags(loop)}`
	end

	got = Split.beat(loop, QUARTER)
	if got ~= "slices 6" or Split.flags(loop) ~= 0 then
		return false, `With the split off, the Heartbeat after the finish ran {got}, flagged {Split.flags(loop)}`
	end

	got = Split.beat(loop, HALF)
	if got ~= "before 7, slices 7, split 7" or Split.flags(loop) ~= Tick.TICKED + Tick.HELD then
		return false, `With the split off, a calm tick ran {got}, flagged {Split.flags(loop)}`
	end

	-- 2) On, the calm count kept while it was off lets the next tick defer
	Tick.useSplit(true)
	if not Tick.splitOn() then
		return false, "Tick.splitOn answered false after Tick.useSplit(true)"
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 7, after 7, slices 7; slices 7; before 8, slices 8, early 8" then
		return false, `The first calm tick after the split went on ran {got}`
	end

	-- 3) Off while the rest waits: the rest still runs at the next Heartbeat, and the next tick runs whole
	Tick.useSplit(false)
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 8, split 8; poll 8, after 8, slices 8; before 9, slices 9, split 9" then
		return false, `With the split turned off while a rest waited, the next three Heartbeats ran {got}`
	elseif Tick.splitOn() then
		return false, "Tick.splitOn answered true after Tick.useSplit(false)"
	end

	-- 4) A flip given anything but a boolean is refused naming its call
	local flipped: boolean, refusal: any = pcall(Tick.useSplit, "on")
	if flipped or not string.find(tostring(refusal), "Tick.useSplit", 1, true) then
		return false, `Tick.useSplit given a string was not refused naming its call: {refusal}`
	end

	return true, nil
end
