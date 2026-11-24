--[[
    A tick defers only while the split stage still held the tick as its
    last run returned: never while it holds nothing, at the next calm tick
    once it holds, and not after a deferred rest that held nothing
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local UNHELD: number = CALM_TICKS + 5 -- The calm ticks run while the split stage holds nothing, past the count
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	loop.Tick.useSplit(true)
	loop.holds = false

	-- 1) Calm past the count, a split stage that never holds defers nothing
	local got: string = Split.calm(loop, UNHELD)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred over {UNHELD} calm ticks whose split stage held nothing: {got}`
	elseif not string.find(got, "split 8, after 8", 1, true) then
		return false, `The calm ticks whose split stage held nothing ran {got}`
	end

	-- 2) Once it holds, the tick that first holds runs whole and the next defers
	loop.holds = true
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 8; slices 8; before 9, slices 9, split 9" then
		return false, `The first tick whose split stage holds ran {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 9, after 9, slices 9; slices 9; before 10, slices 10, early 10" then
		return false, `The tick after the first held one ran {got}`
	end

	-- 3) A deferred rest that holds nothing leaves the next tick whole
	loop.holds = false
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 10, split 10, after 10; slices 10; before 11, slices 11, split 11, after 11" then
		return false, `After a deferred rest that held nothing, the next tick ran {got}`
	end

	return true, nil
end
