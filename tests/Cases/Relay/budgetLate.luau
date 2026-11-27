--[[
    Record by record, a viewer the relay budget leaves one run in four gets
    each record of a 10 Hz target, a 5 Hz target and a player held to the
    out-of-view rate on the run a viewer never left gets it, or one run
    later, and never misses one
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 42 -- Ending on a run the viewer takes, after one it took
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local LOOK: vector = vector.create(0, 0, -1) -- Both viewers look along -Z
local AWAY: vector = vector.create(3000, 0, 0)
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

-- Ahead in the 10 Hz band, ahead in the 5 Hz band, and behind past the example's 40-stud out-of-view radius, where
-- the first band's 20 Hz is held to the out-of-view 5 Hz
local TARGETS: { { name: string, at: vector } } = {
	{ name = "10 Hz", at = vector.create(0, 0, -450) },
	{ name = "5 Hz", at = vector.create(0, 0, -800) },
	{ name = "out of view", at = vector.create(0, 0, 100) },
}

-- A viewer with a body at the origin, looking along -Z
local function seated(harness: any, name: string): any
	local client: any = harness:viewer(name)
	client.viewer.slot = harness:spawn("Player", vector.zero)
	client.viewer.look = LOOK

	return client
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	-- The viewer the budget leaves, and one a moderator watches, so it is never left, seated alike
	local viewer: any = seated(harness, "Viewer")
	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local steady: any = seated(harness, "Steady")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, steady)

	local slots: { number } = {}
	for index: number, target: { name: string, at: vector } in TARGETS do
		slots[index] = harness:spawn("Player", target.at)
	end

	Harness.Relay.setBudget(0)

	local late: { { number } } = { {}, {}, {} }
	local onTime: { { number } } = { {}, {}, {} }
	local waits: number = 0
	for run: number = 1, RUNS do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		for _, call: any in harness.passed do
			if call.key == viewer.viewer.key then
				waits += 1
			end
		end

		for index: number, slot: number in slots do
			for _ = 1, Harness.count(viewer.seen.records, slot) do
				table.insert(late[index], run)
			end

			for _ = 1, Harness.count(steady.seen.records, slot) do
				table.insert(onTime[index], run)
			end
		end
	end

	if waits == 0 then
		return false, "The budget never left the viewer"
	end

	for index: number, target: { name: string, at: vector } in TARGETS do
		local got: { number } = late[index]
		local due: { number } = onTime[index]
		if #got ~= #due then
			return false, `The {target.name} target sent the left viewer {#got} records and the steady one {#due}`
		end

		for place: number, run: number in due do
			if got[place] < run or got[place] > run + 1 then
				return false,
					`The {target.name} target's record {place}, due on run {run}, reached the left viewer on run {got[place]}`
			end
		end
	end

	return true, nil
end
