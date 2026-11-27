--[[
    The split turned off between a deferred tick's first Heartbeat and its
    second: the parked rest still runs, nothing goes twice or goes missing,
    the next tick runs whole, and the history's term is 0 from its decode
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DEFERRING: number = SplitSide.CALM + 1 -- The deferred tick the split goes off during
local NEXT: number = DEFERRING + 1
local AFTER: number = 1 -- Ticks run after the next one

type Driven = SplitSide.Driven

-- Why a tick's arrivals of a kind came other than all on one Heartbeat, or nil
local function onlyAt(split: { { string } }, kind: string, tick: number, beat: number, one: boolean): string?
	local beats: { number } = SplitSide.found(split, kind, tick)
	if #beats == 0 or (one and #beats ~= 1) then
		return `Tick {tick} gave the client {#beats} {kind} arrivals`
	end

	for _, at: number in beats do
		if at ~= beat then
			return `Tick {tick}'s {kind} arrival came at Heartbeat {at}, not {beat}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true, clock = true })
	local side: any = driven.side
	local Tick: any = side.Tick
	local History: any = side.rig:require(side.rig.tread.Server.History)

	SplitSide.ticks(driven, DEFERRING - 1)

	-- The deferring tick's own Heartbeat, the split off before its rest, then the rest and its finish
	driven.file(DEFERRING)
	SplitSide.beat(driven, SplitSide.THIRD)
	local term: number = History.sendLagSeconds()
	Tick.useSplit(false)
	SplitSide.beat(driven, SplitSide.THIRD)
	SplitSide.beat(driven, SplitSide.THIRD)

	-- The next tick's own Heartbeat: it runs whole and holds, and its decode set the term to 0
	driven.file(NEXT)
	SplitSide.beat(driven, SplitSide.THIRD)
	local zeroed: number = History.sendLagSeconds()
	SplitSide.beat(driven, SplitSide.THIRD)
	SplitSide.beat(driven, SplitSide.THIRD)

	driven.tick = NEXT
	SplitSide.ticks(driven, AFTER)

	local own: number = SplitSide.place(DEFERRING, 1)
	local nextOwn: number = SplitSide.place(NEXT, 1)
	local rest: number = driven.flags[own + 1]
	local whole: number = driven.flags[nextOwn]

	if rest ~= Tick.DEFERRED + Tick.HELD then
		return false, `The deferring tick's rest Heartbeat had the flags {rest}, not its rest held`
	elseif whole ~= Tick.TICKED + Tick.HELD then
		return false, `The next tick's own Heartbeat had the flags {whole}, not a whole tick held`
	elseif term == 0 or zeroed ~= 0 then
		return false, `The history's term was {term} at the deferring tick and {zeroed} at the next, not set and then 0`
	end

	-- Each tick's acknowledgment once and its blocks on one Heartbeat: the deferred one's at its finish, two after
	-- its own, and the whole one's at its finish, one after
	local split: { { string } } = SplitSide.segments(side)
	local why: string? = onlyAt(split, "owner", DEFERRING, own + 2, true)
		or onlyAt(split, "relay", DEFERRING, own + 2, false)
		or onlyAt(split, "owner", NEXT, nextOwn + 1, true)
		or onlyAt(split, "relay", NEXT, nextOwn + 1, false)
	if why then
		return false, why
	end

	-- One tap frame each
	local frames: { [number]: number } = {}
	for _, data: string in side.frames.Client do
		local tick: number = side.Tap.read(buffer.fromstring(data)).tick
		frames[tick] = (frames[tick] or 0) + 1
	end

	if frames[DEFERRING] ~= 1 or frames[NEXT] ~= 1 then
		return false, `The client's frames gave tick {DEFERRING} {frames[DEFERRING]} and tick {NEXT} {frames[NEXT]}`
	end

	return true, nil
end
