--[[
    A deferred tick that queued the client's acknowledgment, whose rest is
    skipped by the next tick coming due: that acknowledgment leaves on the
    deferred tick's second Heartbeat, ahead of the next tick's, once each
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DEFERRING: number = SplitSide.CALM + 1 -- The deferred tick whose run the next is owed over
local OWED: number = DEFERRING + 1
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOTS: number = 3 -- The side's bots, each sent its whole OwnerState every tick

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true })
	local side: any = driven.side

	SplitSide.ticks(driven, DEFERRING - 1)
	side.server:stats()

	-- The deferring tick's own Heartbeat, where the client, agreeing, has its acknowledgment queued; then one of a whole
	-- tick, which owes the next before the rest can run; then the next's finish
	driven.file(DEFERRING)
	SplitSide.beat(driven, SplitSide.THIRD)
	driven.file(OWED)
	SplitSide.beat(driven, 1)
	SplitSide.beat(driven, SplitSide.THIRD)

	local first: number = SplitSide.place(DEFERRING, 1)
	if driven.flags[first] ~= side.Tick.TICKED or bit32.band(driven.flags[first + 1], side.Tick.DEFERRED) == 0 then
		return false,
			`The deferring tick's Heartbeats had the flags {driven.flags[first]} and {driven.flags[first + 1]}`
	end

	-- The client's two acknowledgments, and the three bots' whole OwnerStates each tick, as they file no command
	local read: any = side.server:stats()
	if read.relaySkipped ~= 1 or read.ownerAcks ~= 2 or read.ownerFull ~= 2 * BOTS then
		local owners: string = `{read.ownerAcks} acknowledgments and {read.ownerFull} whole OwnerStates`
		return false, `Stats gave {read.relaySkipped} relay ticks skipped, {owners}, not 1, 2 and {2 * BOTS}`
	end

	-- The deferring tick's acknowledgment goes with the owed tick's sends on the Heartbeat after its own, and the owed
	-- tick's with its blocks at its finish
	local split: { { string } } = SplitSide.segments(side)
	for tick: number, beat: number in { [DEFERRING] = first + 1, [OWED] = first + 2 } do
		local beats: { number }, sizes: { number } = SplitSide.found(split, "owner", tick)
		if #beats ~= 1 or beats[1] ~= beat or sizes[1] ~= ACK_BYTES then
			local came: string = `{#beats} Owner messages, the first at Heartbeat {beats[1]} as {sizes[1]} B`
			return false, `Tick {tick} sent the client {came}, not one acknowledgment at {beat}`
		end
	end

	-- Older before newer, as the client takes them
	local last: number = 0
	for _, arrival: string in side.arrivals do
		local at: string? = arrival:match("^owner (%d+)")
		if at then
			local tick: number = tonumber(at) :: number
			if tick <= last then
				return false, `The client heard tick {tick}'s Owner message after tick {last}'s`
			end

			last = tick
		end
	end

	if #SplitSide.found(split, "relay", DEFERRING) ~= 0 then
		return false, `The skipped run still sent the client blocks of tick {DEFERRING}`
	end

	return true, nil
end
