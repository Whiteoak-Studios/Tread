--[[
    With no out-of-view rate the viewer's look changes nothing: a viewer
    whose look points behind its body is sent run for run what one with no
    look is, inside the budget and in a squeeze where the view cone's
    weight, the half space ahead of the body, picks who goes
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local RUNS: number = 20 -- Each phase's
local SOFT: number = 64 * 1000 -- The example's soft budget, in bytes a second
local FLOOR: number = 1 -- A far floor low enough that the queue, not the floor, decides who goes
local STRIDE: number = 0.1
local BEHIND: vector = vector.create(0, 0, 1) -- The look, opposite the facing of a body at a facing of 0

-- Each run's records of the target ahead and the one behind, as "ahead,behind", inside the budget then in a squeeze
local function drive(look: vector?): ({ string }, number, number)
	local Constants: any = Environment.load(CONSTANTS)
	local Harness: any = Environment.load(HARNESS)
	-- No out-of-view rate, and whole records, since the squeeze is counted in 16 B records
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.farFloor = FLOOR
		server.tiers.outOfView = nil
		server.relay.changes = false
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = look

	local ahead: number = harness:spawn("Player", vector.create(0, 0, -500))
	local behind: number = harness:spawn("Player", vector.create(0, 0, 500))
	harness:run()

	-- Room for a block's header, its framing and one record a run but not two, since the framing is under half a record
	local squeeze: number = SOFT - (Constants.RELAY_HEADER_BYTES + 1.5 * Constants.RECORD_BYTES)

	local runs: { string } = {}
	local aheadSqueezed: number, behindSqueezed: number = 0, 0

	for run: number = 1, 2 * RUNS do
		if run == RUNS + 1 then
			harness.traffic = squeeze
		end

		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		harness.states[ahead].position += vector.create(step, 0, 0)
		harness.states[behind].position += vector.create(step, 0, 0)
		harness:run()

		local aheadSent: number = Harness.count(client.seen.records, ahead)
		local behindSent: number = Harness.count(client.seen.records, behind)
		table.insert(runs, `{aheadSent},{behindSent}`)

		if run > RUNS then
			aheadSqueezed += aheadSent
			behindSqueezed += behindSent
		end
	end

	return runs, aheadSqueezed, behindSqueezed
end

return function (): (boolean, string | nil)
	local plain: { string }, ahead: number, behind: number = drive(nil)
	local looking: { string } = drive(BEHIND)

	for run: number, sent: string in plain do
		if looking[run] ~= sent then
			return false, `On run {run} a viewer looking behind got {looking[run]}, where one with no look got {sent}`
		end
	end

	-- The squeeze is one the cone's weight decides, so the comparison above covers the weights
	if ahead <= behind then
		return false, `In the squeeze the target ahead got {ahead} records to the {behind} of the one behind`
	end

	return true, nil
end
