--[[
    Relay.setBands while the far rate under load holds the farthest band
    lowered lowers the new farthest band in its place and gives the old one
    back, and Relay.bands gives the bands as set
--]]

--!strict
local Environment = require("../../Environment")
local UnderLoad = require("../../Fixtures/Relay/UnderLoad")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local BUDGET: number = 1 -- Stand-in seconds, which every run's one read of STEP passes, one viewer leaving none
local STEP: number = 2
local LOWER: { runs: number, scale: number } = { runs = 1, scale = 0.5 } -- Lowered from the second run under it on
local SETTLE: number = 3 -- Runs with no budget first, past both targets' reveals
local BEFORE: number = 4 -- Runs counted lowered on UnderLoad.two's bands
local AFTER: number = 6 -- And then on the three below
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local NEARER_AT: vector = vector.create(0, 0, -400) -- In the farthest of two bands, then the middle of three
local FARTHER_AT: vector = vector.create(0, 0, -800) -- In the farthest band either way
local THREE: { { aim: number, floor: number } } =
	{ { aim = 20, floor = 15 }, { aim = 20, floor = 20 }, { aim = 20, floor = 20 } }
local EDGES: { { enter: number, leave: number } } = { { enter = 200, leave = 220 }, { enter = 600, leave = 660 } }

-- Records over the runs, at the relay's rate unless lowered to half of it: both targets halved on two bands, then
-- only the farther, in the new farthest band
local EXPECTED_BEFORE: { number } = { 2, 2 }
local EXPECTED_AFTER: { number } = { 6, 3 }
local EXPECTED_BANDS: string = "20/15,20/20,20/20"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, UnderLoad.two)
	local Relay: any = Harness.Relay

	local viewer: any = harness:viewer("Viewer")
	local slots: { number } = { harness:spawn("Player", NEARER_AT), harness:spawn("Player", FARTHER_AT) }

	local counted: { number } = { 0, 0 }
	local function runs(count: number)
		counted = { 0, 0 }
		for run: number = 1, count do
			for _, slot: number in slots do
				harness.states[slot].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
			end

			harness:run()
			for index: number, slot: number in slots do
				counted[index] += Harness.count(viewer.seen.records, slot)
			end
		end
	end

	runs(SETTLE)
	harness.step = STEP
	Relay.setBudget(BUDGET)
	Relay.setUnderLoad(LOWER)

	-- The run that judges the first over lowers the band for the runs after it
	runs(1)
	runs(BEFORE)
	if counted[1] ~= EXPECTED_BEFORE[1] or counted[2] ~= EXPECTED_BEFORE[2] then
		return false, `On two bands lowered the targets sent {counted[1]} and {counted[2]} records over {BEFORE} runs`
	end

	Relay.setBands(THREE, EDGES)
	runs(AFTER)
	if counted[1] ~= EXPECTED_AFTER[1] or counted[2] ~= EXPECTED_AFTER[2] then
		return false,
			`On three bands the middle and farthest targets sent {counted[1]} and {counted[2]} records over {AFTER} runs`
	end

	local bands: { { aim: number, floor: number } } = Relay.bands()
	local listed: { string } = {}
	for index: number, band: { aim: number, floor: number } in bands do
		listed[index] = `{band.aim}/{band.floor}`
	end

	if table.concat(listed, ",") ~= EXPECTED_BANDS then
		return false, `Relay.bands gave {table.concat(listed, ",")} while lowered, not {EXPECTED_BANDS} as set`
	end

	return true, nil
end
