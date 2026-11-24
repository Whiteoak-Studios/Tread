--[[
    Anti-ESP's passed port is called once for each viewer the relay budget
    leaves, with the viewer table its asks are handed and the slots its view
    tracks with their count, never for a viewer that took its turn, in
    process and on 2 stand-in workers, where it waits for the round's finish
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local VIEWERS: number = 4 -- So each run leaves one
local SETTLE: number = 2 -- Runs with no budget first, so every view tracks both targets
local RUNS: number = 8
local STRIDE: number = 0.1 -- Studs the targets move a run, so every viewer always has a record to send
local TARGETS: { vector } = { vector.create(0, 0, -60), vector.create(40, 0, -80) }

-- Runs the budget's runs and gives why the port was called otherwise, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local clients: { [any]: any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 10, 0, 0)
		clients[client.viewer.key] = client
	end

	local targets: { number } = {}
	for _, at: vector in TARGETS do
		table.insert(targets, harness:spawn("Player", at))
	end

	table.sort(targets)
	local expected: string = table.concat(targets, " ")

	for run: number = 1, SETTLE + RUNS do
		if run == SETTLE + 1 then
			Harness.Relay.setBudget(0)
		end

		for _, slot: number in targets do
			harness.states[slot].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		end

		harness:run()

		local calls: { any } = harness.passed
		if run <= SETTLE then
			if #calls ~= 0 then
				return `Run {run}, with no budget, passed {#calls} viewers`
			end

			continue
		elseif #calls ~= 1 then
			return `Run {run} passed {#calls} viewers, not the 1 it left`
		end

		local call: any = calls[1]
		local slots: { number } = table.clone(call.slots)
		table.sort(slots)
		if call.count ~= #TARGETS or table.concat(slots, " ") ~= expected then
			return `Run {run} passed {call.count} slots, {table.concat(slots, " ")}, not the tracked {expected}`
		end

		for key: any, client: any in clients do
			local turned: boolean = #client.seen.sizes > 0
			if turned == (key == call.key) then
				return `Run {run} passed {client.viewer.key.Name} when it took its turn {turned}`
			elseif key == call.key and call.viewer ~= client.viewer then
				return `Run {run} passed {client.viewer.key.Name} in another table than the one its asks are handed`
			end
		end
	end

	-- On workers the round's finish passes the viewer left, inside the hold, and its dispatch passes nobody
	if workers then
		harness.passed = {}
		harness.tick += 1
		Harness.Relay.run(harness.tick, harness.viewers, harness.states, harness.commands, harness.platforms)
		if #harness.passed ~= 0 then
			return `The dispatch passed {#harness.passed} viewers before its round came in`
		end

		harness.pool:deliver()
		Harness.Relay.finish()
		if #harness.passed ~= 1 then
			return `The round's finish passed {#harness.passed} viewers, not the 1 its run left`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = drive(Environment.load(HARNESS), nil)
	if why then
		return false, `In process: {why}`
	end

	why = drive(Layouts.harness(), WORKERS)
	if why then
		return false, `On {WORKERS} workers: {why}`
	end

	return true, nil
end
