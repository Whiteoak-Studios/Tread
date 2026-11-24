--[[
    A recent shooter held outside a crowd cap of 2 by its distance keeps its
    raise to shotNear.rate over the cap's 5 Hz, while the other player
    outside the cap with no shot is held to it
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local SETTLE: number = 4 -- Runs before the count starts, past each target's reveal
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth, so each always has a change to send
local CROWD: { size: number, rate: number, floor: number } = { size = 2, rate = 5, floor = 5 }

-- Studs ahead of the viewer, all inside the first band: the two members, the plain player outside the cap, and the
-- shooter, whose key over its weight of 3 still trails the plain player's
local DISTANCES: { number } = { 100, 110, 120, 300 }
local SHOOTER: number = 4

-- The records each got over the runs: the members at 20 a second, the plain one at the cap's 5, the shooter at 10
local EXPECTED: { number } = { 40, 40, 10, 20 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, function (shared: any, server: any)
		Bands.three(shared, server)
		server.tiers.crowd = CROWD
	end)

	-- Facing along -Z, so every target ahead of it is in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	local targets: { number } = {}
	for index: number, distance: number in DISTANCES do
		targets[index] = harness:spawn("Player", vector.create(0, 0, -distance))
	end

	local counts: { number } = table.create(#targets, 0)
	for run: number = 1, SETTLE + RUNS do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in targets do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		-- The shot's raise lasts the example's 5 s, past every counted run
		if run == 1 then
			Harness.Relay.shotNear(client.viewer.key, targets[SHOOTER])
		elseif run > SETTLE then
			for index: number, slot: number in targets do
				counts[index] += Harness.count(client.seen.records, slot)
			end
		end
	end

	for index: number, expected: number in EXPECTED do
		if counts[index] ~= expected then
			local got: string = `{counts[index]} records over {RUNS} runs, not {expected}`
			return false, `The player {DISTANCES[index]} studs ahead got {got} ({table.concat(counts, ", ")})`
		end
	end

	return true, nil
end
