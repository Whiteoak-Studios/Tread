--[[
    A tick owed when a deferred rest is due counts as a release counts it:
    the split stage's latest skips the rest, its early part's time kept as
    the tick's one entry, the stages after it and the next tick run on time
    in today's shape, and the calm count starts again
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 20 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local WHOLE: number = 1 -- A share that owes a whole tick at the deferred rest's Heartbeat
local SPIN: number = 0.005 -- Seconds tick 21's early part holds the loop
local EARLY_FLOOR: number = SPIN / 2 -- Below the early part's spin, and above an entry that kept none of its time

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}`
	loop.spins.early = SPIN
	got = `{got}; {Split.beat(loop, HALF)}`
	loop.spins.early = 0

	if got ~= "poll 20, after 20, slices 20; slices 20; before 21, slices 21, early 21" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 1) The rest's Heartbeat owes tick 22: the rest is skipped as a catch-up skips it, the stage after it runs, then
	-- tick 22 whole with its slice
	got = Split.beat(loop, WHOLE)
	local flags: number = Tick.DEFERRED + Tick.TICKED + Tick.HELD
	if got ~= "after 21, before 22, slices 22, split 22" or Split.flags(loop) ~= flags then
		return false, `A rest's Heartbeat that owed a tick ran {got}, flagged {Split.flags(loop)}`
	end

	-- 2) The split stage keeps one entry a tick, tick 21's holding its early part's time
	local stage: any = Split.stage(loop)
	local ticks: { string } = {}
	for index: number = 1, stage.held do
		table.insert(ticks, `{stage.ticks[index]}`)
	end

	local listed: string = table.concat(ticks, ",")
	if stage.held ~= 22 or stage.ticks[21] ~= 21 or stage.ticks[22] ~= 22 then
		return false, `The split stage's ring holds the ticks {listed}, not one entry each from 1 to 22`
	elseif not (stage.times[21] >= EARLY_FLOOR) then
		return false, `Tick 21's entry holds {stage.times[21]} s, under its early part's {SPIN} s spin`
	end

	-- 3) The calm count starts again: tick 22 ran beside the rest and counts nothing, so 20 calm ticks after it pass
	-- before the next defers
	got = Split.calm(loop, CALM_TICKS)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred within {CALM_TICKS} calm ticks of a tick owed at a rest: {got}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 42, after 42, slices 42; slices 42; before 43, slices 43, early 43" then
		return false, `The tick {CALM_TICKS} calm ticks after the one owed at a rest ran {got}`
	end

	return true, nil
end
