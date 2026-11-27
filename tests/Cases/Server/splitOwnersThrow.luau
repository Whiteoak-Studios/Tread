--[[
    An owners' part that throws at one owner: under the split the early
    flush still goes, one stage report names relay, that owner and those
    after it get no OwnerState, and every viewer still gets the tick's
    blocks; with the split off the same throw stops the tick's relay run
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local THROW_AT: number = SplitSide.CALM + 1 -- The tick whose owners' part throws, a deferred one with the split on
local AFTER: number = 2 -- Ticks run after it
local THROWER: string = "Seen" -- The owner whose ping sample throws, the second in the order the characters were made
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" } -- In that order
local PLANTED: string = "A planted failure in one owner's ping sample"

type Driven = SplitSide.Driven

-- A side whose thrower's ping sample throws on THROW_AT's own Heartbeat, run through that tick and AFTER more
local function run(split: boolean): Driven
	local driven: Driven = SplitSide.new({ split = split, workers = true })
	local side: any = driven.side
	SplitSide.ticks(driven, THROW_AT - 1)

	-- The owners' part samples each owner's ping just before its OwnerState, so the throw stops it there
	local connection: any = side.rig:require(side.rig.tread.Server.Connections).get(side.keys[THROWER])
	connection.sample = function ()
		error(PLANTED)
	end

	SplitSide.beat(driven, SplitSide.THIRD)
	connection.sample = nil
	SplitSide.beat(driven, SplitSide.THIRD)
	SplitSide.beat(driven, SplitSide.THIRD)

	driven.tick = THROW_AT
	SplitSide.ticks(driven, AFTER)

	return driven
end

-- Each viewer's tap frame for THROW_AT, by name
local function framed(driven: Driven): { [string]: any }
	local side: any = driven.side
	local frames: { [string]: any } = {}

	for _, name: string in NAMES do
		for _, data: string in side.frames[name] do
			local frame: any = side.Tap.read(buffer.fromstring(data))
			if frame.tick == THROW_AT then
				frames[name] = frame
			end
		end
	end

	return frames
end

-- Why the side's stage reports were other than one for relay, or nil
local function reportedOnce(driven: Driven, label: string): string?
	local reported: { number | string } = driven.side.rig:reported("stage")
	if #reported ~= 1 or reported[1] ~= "relay" then
		return `{label}, the stage reports were {#reported}, the first {reported[1]}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local on: Driven = run(true)
	local own: number = SplitSide.place(THROW_AT, 1)
	local split: { { string } } = SplitSide.segments(on.side)

	if bit32.band(on.flags[own + 1], on.side.Tick.DEFERRED) == 0 then
		return false, `Tick {THROW_AT} did not defer with the split on, its next Heartbeat's flags {on.flags[own + 1]}`
	end

	local once: string? = reportedOnce(on, "With the split on")
	if once then
		return false, once
	end

	-- The owner before the thrower got its OwnerState in the early flush, once, and the rest of the tick sent no other
	local owners: { number } = SplitSide.found(split, "owner", THROW_AT)
	if #owners ~= 1 or owners[1] ~= own then
		return false,
			`With the split on, the client's OwnerState of tick {THROW_AT} came at "{table.concat(owners, ", ")}"`
	end

	-- Every viewer's frame still carries the tick's blocks, and only the client's an OwnerState
	local onFrames: { [string]: any } = framed(on)
	for _, name: string in NAMES do
		local frame: any = onFrames[name]
		local owned: boolean = name == "Client"
		if not frame or #frame.blocks == 0 then
			return false, `With the split on, {name}'s tap frame for tick {THROW_AT} carried no block`
		elseif (frame.owner ~= nil) ~= owned then
			return false, `With the split on, {name}'s tap frame for tick {THROW_AT} carried an OwnerState {not owned}`
		end
	end

	local blocks: { number } = SplitSide.found(split, "relay", THROW_AT)
	if #blocks == 0 or blocks[1] ~= own + 2 then
		return false, `With the split on, the client's blocks of tick {THROW_AT} came at {blocks[1]}, not {own + 2}`
	end

	-- With it off the throw stops the tick's relay run, so no viewer gets its blocks, while the next tick's go
	local off: Driven = run(false)
	local offOnce: string? = reportedOnce(off, "With the split off")
	if offOnce then
		return false, offOnce
	end

	local offFrames: { [string]: any } = framed(off)
	for _, name: string in NAMES do
		local frame: any = offFrames[name]
		if not frame or #frame.blocks ~= 0 then
			return false,
				`With the split off, {name}'s tap frame for tick {THROW_AT} carried blocks, or came not at all`
		end
	end

	local offSplit: { { string } } = SplitSide.segments(off.side)
	if #SplitSide.found(offSplit, "relay", THROW_AT) ~= 0 then
		return false, `With the split off, the client was still sent blocks of tick {THROW_AT}`
	elseif #SplitSide.found(offSplit, "relay", THROW_AT + 1) == 0 then
		return false, `With the split off, the client got no blocks of tick {THROW_AT + 1}`
	end

	return true, nil
end
