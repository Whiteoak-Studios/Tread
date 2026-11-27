--[[
    The mark that a viewer's turn follows a run the relay budget left it
    crosses to its worker in the hand-in, so on 1 and 2 stand-in workers each
    viewer's blocks over the dev place's three bands digest as in process,
    where the viewers left go first and a worker's are sent in list order
--]]

--!strict
local serde = require("@lune/serde")

local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST_WORKERS: number = 2
local VIEWERS: number = 4 -- So each run leaves one
local RUNS: number = 24
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send

-- Targets in each of the three bands from the viewers, whose credit after a wait is what the mark changes
local TARGETS: { vector } = {
	vector.create(0, 0, -100),
	vector.create(0, 0, -450),
	vector.create(0, 0, -800),
	vector.create(500, 0, 0),
}

-- Every block each viewer was sent, in its own order and with the run it came in, one viewer after another, and the
-- viewers left
local function drive(Harness: any, workers: number?): (string, number)
	local harness: any = Harness.new(nil, Bands.three, workers)
	local parts: { [any]: { string } } = {}
	local run: number = 0

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		for _, key: any in keys do
			table.insert(parts[key], `run {run} {buffer.tostring(data)}`)
		end

		Harness._deliver(self, keys, data)
	end

	local keys: { any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 10, 0, 0)
		parts[client.viewer.key] = {}
		table.insert(keys, client.viewer.key)
	end

	local slots: { number } = {}
	for _, at: vector in TARGETS do
		table.insert(slots, harness:spawn("Player", at))
	end

	Harness.Relay.setBudget(0)

	for index: number = 1, RUNS do
		run = index
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()
	end

	local joined: { string } = {}
	for index: number, key: any in keys do
		joined[index] = `{key.Name}\n{table.concat(parts[key], "\n")}`
	end

	local left: number = Harness.Relay.caps()

	return serde.hash("sha256", table.concat(joined, "\n")), left
end

return function (): (boolean, string | nil)
	local digest: string, left: number = drive(Environment.load(HARNESS), nil)
	if left ~= RUNS then
		return false, `In process the budget left {left} viewer turns over {RUNS} runs, not one a run`
	end

	for workers: number = 1, MOST_WORKERS do
		local onWorkers: string, workersLeft: number = drive(Layouts.harness(), workers)
		if onWorkers ~= digest or workersLeft ~= left then
			return false,
				`On {workers} workers the blocks digest to {onWorkers} with {workersLeft} left, not {digest} with {left}`
		end
	end

	return true, nil
end
