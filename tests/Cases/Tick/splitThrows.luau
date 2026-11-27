--[[
    A throw in the slice on a deferred rest's Heartbeat, or in a stage after
    the split stage at the release or in the rest, is reported as that
    stage's, every later stage still runs, and nothing is left held
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick

	-- A last stage, after the one that throws, so the case sees what runs after it
	Tick.addStage("tail", "after", function (tick: number)
		table.insert(loop.order, `tail {tick}`)
	end)

	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local got: string = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "poll 3, after 3, tail 3, slices 3; slices 3; before 4, slices 4, early 4" then
		return false, `The tick after {CALM_TICKS} calm ones ran {got}`
	end

	-- 1) The slice throws before the rest: reported, and the rest still runs and holds
	loop.faults["slices 4"] = "throws"
	got = Split.beat(loop, QUARTER)
	loop.faults["slices 4"] = nil

	if got ~= "slices 4, split 4" or Split.flags(loop) ~= Tick.DEFERRED + Tick.HELD then
		return false, `A rest's Heartbeat whose slice threw ran {got}, flagged {Split.flags(loop)}`
	elseif table.concat(loop.reports, ", ") ~= "stage slices" then
		return false, `A slice that threw before a rest left the reports {table.concat(loop.reports, ", ")}`
	end

	-- 2) The stage after the split stage throws at the release: the stage after it and the slice still run
	loop.faults["after 4"] = "throws"
	got = Split.beat(loop, QUARTER)
	if got ~= "poll 4, after 4, tail 4, slices 4" or Tick.holding() then
		return false, `A release whose later stage threw ran {got}, holding {Tick.holding()}`
	elseif table.concat(loop.reports, ", ") ~= "stage slices, stage after" then
		return false, `A later stage that threw at a release left the reports {table.concat(loop.reports, ", ")}`
	end

	-- 3) It throws in the rest itself: the stage after it still runs, nothing is held, and the loop goes on
	got = Split.beat(loop, HALF)
	if got ~= "before 5, slices 5, early 5" then
		return false, `The next calm tick ran {got}, not deferred`
	end

	loop.holds = false
	loop.faults["after 5"] = "throws"
	got = Split.beat(loop, QUARTER)
	if got ~= "slices 5, split 5, after 5, tail 5" or Split.flags(loop) ~= Tick.DEFERRED or Tick.holding() then
		return false, `A rest whose later stage threw ran {got}, flagged {Split.flags(loop)}`
	elseif #loop.reports ~= 3 then
		return false, `A later stage that threw in a rest left the reports {table.concat(loop.reports, ", ")}`
	end

	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, HALF)}`
	if got ~= "slices 5; before 6, slices 6, split 6, after 6, tail 6" then
		return false, `After a rest whose later stage threw, the loop ran {got}`
	end

	return true, nil
end
