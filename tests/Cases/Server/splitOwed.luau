--[[
    A tick owed on a deferred tick's next Heartbeat skips the deferred
    tick's relay run, counted in relaySkipped, while its OwnerState has
    already gone, and the tick owed runs whole and holds in its place
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DEFERRING: number = SplitSide.CALM + 1 -- The deferred tick whose run the next is owed over
local OWED: number = DEFERRING + 1
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true })
	local side: any = driven.side
	local Tick: any = side.Tick

	-- The deferring tick goes as a whole OwnerState, the client filing no command for it
	driven.full[DEFERRING] = true
	SplitSide.ticks(driven, DEFERRING - 1)
	side.server:stats()

	-- The deferring tick's own Heartbeat, then one of a whole tick, which owes the next tick before the rest can run
	SplitSide.beat(driven, SplitSide.THIRD)
	driven.file(OWED)
	SplitSide.beat(driven, 1)
	SplitSide.beat(driven, SplitSide.THIRD)

	local first: number = SplitSide.place(DEFERRING, 1)
	local owed: number = driven.flags[first + 1]
	if driven.flags[first] ~= Tick.TICKED or owed ~= Tick.TICKED + Tick.HELD + Tick.DEFERRED then
		return false, `The deferring tick's Heartbeat had the flags {driven.flags[first]} and the next {owed}`
	end

	local read: any = side.server:stats()
	if read.relaySkipped ~= 1 or read.ticks ~= 2 then
		return false, `Stats gave {read.relaySkipped} relay ticks skipped over {read.ticks} ticks, not 1 over 2`
	end

	local split: { { string } } = SplitSide.segments(side)
	local owners: { number }, sizes: { number } = SplitSide.found(split, "owner", DEFERRING)
	local skipped: { number } = SplitSide.found(split, "relay", DEFERRING)
	local dispatched: { number } = SplitSide.found(split, "dispatch", DEFERRING)

	if #owners ~= 1 or owners[1] ~= first or sizes[1] <= ACK_BYTES then
		return false,
			`The deferring tick's whole OwnerState came at Heartbeats {table.concat(owners, ", ")}, not {first}`
	elseif #skipped ~= 0 or #dispatched ~= 0 then
		return false, `The skipped run still went: {#dispatched} dispatches and {#skipped} blocks`
	end

	-- The tick owed dispatches on the Heartbeat it ran and sends at its finish, as without the split
	local blocks: { number } = SplitSide.found(split, "relay", OWED)
	local sent: { number } = SplitSide.found(split, "dispatch", OWED)
	if #sent ~= 1 or sent[1] ~= first + 1 or #blocks == 0 or blocks[1] ~= first + 2 then
		return false, `The owed tick was dispatched at Heartbeat {sent[1]} and its blocks came at {blocks[1]}`
	end

	local reported: { number | string } = side.rig:reported("stage")
	if #reported ~= 0 then
		return false, `The stages reported {#reported} failures, the first {reported[1]}`
	end

	return true, nil
end
