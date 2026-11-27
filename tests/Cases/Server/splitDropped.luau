--[[
    A deferred tick's round given up past relay.timeout, on a stand-in
    clock: no send time is measured, the history's term keeps its value,
    the tick's tap frames still come, and the next tick's blocks go out
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DROP_AT: number = SplitSide.CALM + 1 -- The deferred tick whose round is never delivered
local PAST: number = 61 -- Seconds the stand-in clock is moved before the finish's Heartbeat, past the 60 s timeout
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true, clock = true })
	local side: any = driven.side
	local History: any = side.rig:require(side.rig.tread.Server.History)
	local clock: { now: number } = driven.clock :: { now: number }

	SplitSide.ticks(driven, DROP_AT - 1)
	local before: number = side.server:stats().relaySend

	-- The deferring tick's own Heartbeat, then its rest's, whose round stays out, then its finish's, past the timeout
	driven.file(DROP_AT)
	SplitSide.beat(driven, SplitSide.THIRD)
	local term: number = History.sendLagSeconds()

	driven.deliver = false
	SplitSide.beat(driven, SplitSide.THIRD)
	driven.deliver = true
	clock.now += PAST
	SplitSide.beat(driven, SplitSide.THIRD)

	local own: number = SplitSide.place(DROP_AT, 1)
	if bit32.band(driven.flags[own + 1], side.Tick.DEFERRED) == 0 then
		return false, `Tick {DROP_AT} did not defer, its next Heartbeat's flags {driven.flags[own + 1]}`
	end

	local read: any = side.server:stats()
	if read.relayDropped ~= 1 then
		return false, `Stats gave {read.relayDropped} rounds given up, not the one`
	elseif read.relaySend ~= before then
		return false, `The given-up round moved relaySend from {before} to {read.relaySend}`
	elseif term == 0 then
		return false, "The history's term was 0 at the deferring tick, so the case shows nothing of it"
	end

	-- The finish still made each viewer's frame for the tick, with no block from the workers
	for _, name: string in NAMES do
		local found: any = nil
		for _, data: string in side.frames[name] do
			local frame: any = side.Tap.read(buffer.fromstring(data))
			if frame.tick == DROP_AT then
				found = frame
			end
		end

		if not found or #found.blocks ~= 0 then
			return false, `{name}'s tap frame for tick {DROP_AT} came {found ~= nil} with blocks from the dropped round`
		elseif not found.owner or buffer.readu16(found.owner.data, 2) ~= DROP_AT then
			return false, `{name}'s tap frame for tick {DROP_AT} carried no OwnerState of its tick`
		end
	end

	-- The next tick decodes with the term as it was, and its blocks go out, the dropped tick's never
	driven.tick = DROP_AT
	SplitSide.ticks(driven, 1)

	local split: { { string } } = SplitSide.segments(side)
	if History.sendLagSeconds() ~= term then
		return false, `After the given-up round the history's term was {History.sendLagSeconds()}, not {term}`
	elseif #SplitSide.found(split, "relay", DROP_AT) ~= 0 then
		return false, `The client was sent blocks of the given-up tick {DROP_AT}`
	elseif #SplitSide.found(split, "relay", DROP_AT + 1) == 0 then
		return false, `The client got no blocks of tick {DROP_AT + 1}, the one after the given-up round`
	end

	return true, nil
end
