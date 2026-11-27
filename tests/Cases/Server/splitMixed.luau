--[[
    One player's turns in process beside the client's on a worker, both
    agreeing, deferring: the in-process player's blocks leave on frame 2 and
    its acknowledgment on frame 3, the client's blocks and acknowledgment
    together on frame 3, and the history's term follows the finish's measure
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DEFERRING: number = SplitSide.CALM + 1 -- A deferred tick, the one read
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local RATE: number = 20 -- The example's relay rate, Hz
local SMOOTHING: number = 1 -- The example's rewind.rttSmoothing, seconds
local TOLERANCE: number = 1e-12 -- Seconds two sums of the same exact steps may part by
local PLACE: { number } = { 3, -6 } -- Where the in-process player's character is built, x and z over the floor

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true, clock = true })
	local side: any = driven.side
	local Relay: any = side.rig:require(side.rig.tread.Server.Relay)
	local History: any = side.rig:require(side.rig.tread.Server.History)

	-- Every first view is made on a worker on tick 1; the second player's, made on tick 2, stays in process
	SplitSide.ticks(driven, 1)
	Relay.useWorkers(false)
	local near: SplitSide.Listener = SplitSide.listener(driven)
	side.server:create(near.key, side.rig:at(PLACE[1], PLACE[2]))
	SplitSide.ticks(driven, 1)
	Relay.useWorkers(true)

	-- Every tick holds for the client's round: one Heartbeat to the finish before the split, two once it defers
	local send: number? = nil
	for tick: number = 1, DEFERRING - 1 do
		local measure: number = (tick >= SplitSide.CALM and 2 or 1) * SplitSide.STEP
		send = send and send + (1 - math.exp(-1 / RATE / SMOOTHING)) * (measure - send) or measure
	end

	SplitSide.ticks(driven, DEFERRING - 2)
	local term: number = History.sendLagSeconds()
	SplitSide.ticks(driven, 1)

	local own: number = SplitSide.place(DEFERRING, 1)
	if bit32.band(driven.flags[own + 1], side.Tick.DEFERRED) == 0 then
		return false, `Tick {DEFERRING} did not defer, its next Heartbeat's flags {driven.flags[own + 1]}`
	end

	-- The history's term at the deferring tick's decode is the finish's measure up to the tick before
	local expected: number = send :: number
	if math.abs(term - expected) > TOLERANCE then
		return false, `The history's term at tick {DEFERRING} was {term}, not the finish's {expected}`
	end

	-- The client's view is on a worker: its blocks and acknowledgment leave together at the finish
	local split: { { string } } = SplitSide.segments(side)
	local owners: { number }, sizes: { number } = SplitSide.found(split, "owner", DEFERRING)
	local blocks: { number } = SplitSide.found(split, "relay", DEFERRING)
	if #owners ~= 1 or owners[1] ~= own + 2 or sizes[1] ~= ACK_BYTES then
		return false,
			`The client's Owner message of tick {DEFERRING} came at {owners[1]} as {sizes[1]} B, not {own + 2}`
	end

	for _, beat: number in blocks do
		if beat ~= own + 2 then
			return false, `A block of tick {DEFERRING} reached the client at Heartbeat {beat}, not {own + 2}`
		end
	end

	-- The second player's view is in process: its blocks leave at the dispatch, its acknowledgment at the finish
	local heardOwners: { number }, heardSizes: { number } = SplitSide.heardOf(near, "owner", DEFERRING)
	local heardBlocks: { number } = SplitSide.heardOf(near, "relay", DEFERRING)
	if #heardOwners ~= 1 or heardOwners[1] ~= own + 2 or heardSizes[1] ~= ACK_BYTES then
		local came: string = `at {heardOwners[1]} as {heardSizes[1]} B`
		return false, `The in-process player's Owner message of tick {DEFERRING} came {came}, not {own + 2}`
	elseif #heardBlocks == 0 or #blocks == 0 then
		return false, `Tick {DEFERRING} sent {#heardBlocks} blocks in process and {#blocks} to the client`
	end

	for _, beat: number in heardBlocks do
		if beat ~= own + 1 then
			return false, `A block of tick {DEFERRING} reached the in-process player at Heartbeat {beat}, not {own + 1}`
		end
	end

	return true, nil
end
