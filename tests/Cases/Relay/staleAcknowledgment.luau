--[[
    A moderator's client acknowledges the blocks of the view it last had
    for a while after a spectate starts or ends, so the next view's blocks
    are numbered past the newest it was sent there, and a stale word clears
    nothing the moderator never read
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local SEQUENCE: string = "src/Codec/Sequence.luau"
local SETTLED: number = 3 -- Runs every acknowledgment takes to settle at the moderator's lag
local AHEAD: number = 10 -- Runs the moderator's own view numbers blocks for before the target's starts
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local BESIDE_AWAY: vector = vector.create(4010, 0, 0)
local NEAR: vector = vector.create(20, 0, 0)
local STRIDE: vector = vector.create(0, 0, 0.5)
local LAG: number = 2 -- Runs the moderator's acknowledgment takes to arrive

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Sequence: any = Environment.load(SEQUENCE)
	local harness: any = Harness.new()

	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY
	moderator.lag = LAG

	-- The moderator's own view sends a block a run, so its sequences run ahead of the target's, which starts later
	local walker: number = harness:spawn("Player", BESIDE_AWAY)
	for _ = 1, AHEAD do
		harness.states[walker].position += STRIDE
		harness:run()
	end

	local target: any = harness:viewer("Target")
	local seen: number = harness:spawn("Player", NEAR)
	harness:runs(SETTLED)

	-- The start's reveal is lost on its way to the moderator, whose word still names its own view's blocks
	local heard: number = moderator.newest
	harness:watch(moderator, target)
	Harness.Relay.revealAll(target.viewer.key)
	moderator.lose = 1
	harness:run()

	if moderator.seen.lost ~= 1 then
		return false, "The start's copy was not sent to the moderator"
	end

	local copied: boolean = false
	for _ = 1, LAG + SETTLED do
		harness:run()

		for _, sequence: number in moderator.seen.sequences do
			if Sequence.difference(sequence, heard) <= 0 then
				return false,
					`The target's block {sequence} was not numbered past {heard}, the moderator's last own block`
			end
		end

		if Harness.count(moderator.seen.reveals, seen) > 0 then
			copied = true
		end
	end

	if not copied then
		return false, "A stale acknowledgment from the moderator's own view cleared the reveal it lost"
	end

	-- The end: the moderator's own blocks go on past the newest copy of the target's it was sent
	heard = moderator.newest
	harness:watch(moderator, nil)
	Harness.Relay.revealAll(moderator.viewer.key)
	harness.states[walker].position += STRIDE
	harness:run()

	if #moderator.seen.sequences == 0 then
		return false, "The moderator's own view sent it nothing at the spectate's end"
	end

	for _, sequence: number in moderator.seen.sequences do
		if Sequence.difference(sequence, heard) <= 0 then
			return false, `The moderator's own block {sequence} was not numbered past {heard}, its last copy`
		end
	end

	return true, nil
end
