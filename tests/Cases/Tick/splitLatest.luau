--[[
    With a latest that runs the split stage on even ticks alone, as a relay
    at half the simulation's rate, a Heartbeat owing two ticks runs it on
    its first, and that tick runs it whole, since only a lone tick defers
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 21 -- The calm ticks run first, ending on an odd one, so 20 were calm before tick 22
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local TWO_OWED: number = 1.5 -- The share that, after two quarters, owes two ticks at once

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	loop.latest = function (tick: number): boolean
		return tick % 2 == 0
	end

	local got: string = Split.calm(loop, CALM_TICKS)
	if string.find(got, "early", 1, true) then
		return false, `A tick deferred in the first {CALM_TICKS} calm ticks: {got}`
	elseif not string.find(got, "before 21, slices 21, after 21", 1, true) then
		return false, `The calm ticks ran {got}, not the split stage on even ticks alone`
	end

	-- Ticks 22 and 23 on one Heartbeat: the split stage's latest runs it on 22, the first, which holds and runs whole
	got = `{Split.beat(loop, QUARTER)}; {Split.beat(loop, QUARTER)}; {Split.beat(loop, TWO_OWED)}`
	if
		got ~= "slices 21; slices 21; before 22, slices 22, split 22"
		or Split.flags(loop) ~= Tick.TICKED + Tick.HELD
	then
		return false,
			`A Heartbeat owing two ticks whose first runs the split stage ran {got}, flagged {Split.flags(loop)}`
	end

	return true, nil
end
