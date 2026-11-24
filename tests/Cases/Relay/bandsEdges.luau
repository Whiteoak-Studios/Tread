--[[
    A player walked out through both band edges and back is held at each
    stop for a count of records that names its band: in under an edge's
    enter, out only past its leave, at 350 and 385 studs and at 600 and 660
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local SETTLE: number = 4 -- Runs at the first stop before the counts start, past the target's reveal
local HOLD: number = 8 -- Runs at each stop, so 20, 10 and 5 Hz give 8, 4 and 2 records there
local SWAY: number = 0.05 -- Studs the target steps either side across the line, so it always has a change to send

-- Studs ahead of the viewer, out through each edge and back, with the records each stop gave
local WALK: { number } = { 349, 360, 384, 386, 599, 650, 661, 650, 599, 386, 384, 360, 349 }
local EXPECTED: { number } = { 8, 8, 8, 4, 4, 4, 2, 2, 4, 4, 4, 4, 8 }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	-- Facing along -Z, so the target ahead of it stays in its view
	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)
	local target: number = harness:spawn("Player", vector.create(0, 0, -WALK[1]))

	-- One run with the target a distance ahead, stepped to one side or the other of the line
	local function stand(distance: number, run: number)
		local sway: number = SWAY
		if run % 2 == 0 then
			sway = -SWAY
		end

		harness.states[target].position = vector.create(sway, 0, -distance)
		harness:run()
	end

	for run: number = 1, SETTLE do
		stand(WALK[1], run)
	end

	local counts: { number } = {}
	for stop: number, distance: number in WALK do
		counts[stop] = 0
		for run: number = 1, HOLD do
			stand(distance, run)
			counts[stop] += Harness.count(client.seen.records, target)
		end
	end

	for stop: number, expected: number in EXPECTED do
		if counts[stop] ~= expected then
			local got: string = `{counts[stop]} records in {HOLD} runs, not {expected}`
			return false, `Stop {stop}, {WALK[stop]} studs out, got {got} ({table.concat(counts, ", ")})`
		end
	end

	return true, nil
end
