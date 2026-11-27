--[[
    A zoomed viewer's players outside a crowd cap of 1 aim for the lower of
    the first band's aim and the cap's rate wherever they stand, while its
    one member keeps the first band's
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local SETTLE: number = 4 -- Runs before the count starts, past each target's reveal
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth, so each always has a change to send
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 10, floor = 5 }

-- Studs ahead of the viewer: the member in the first band, then the rest in each of the three bands
local DISTANCES: { number } = { 100, 120, 450, 800 }

-- The records each got over the runs: the member at the first band's 20 a second, and each of the rest at the cap's
-- 10, below the 20 the zoom gives it and above the 5 the last one's own band aims for
local EXPECTED: { number } = { 40, 20, 20, 20 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, function (shared: any, server: any)
		Bands.three(shared, server)
		server.tiers.crowd = CROWD
	end)

	-- Facing along -Z, so every target ahead of it is in its view, and looking through a scope
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.zoomed = true

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

		if run > SETTLE then
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
