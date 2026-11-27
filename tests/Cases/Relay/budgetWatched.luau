--[[
    Under a relay budget of 0 a target a moderator watches is never left, the
    other viewers taking the wait, and the moderator gets every block the
    target does, in process and on 2 stand-in workers
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local VIEWERS: number = 4 -- So a run may leave one, the target first in line were it not watched
local RUNS: number = 12
local STRIDE: number = 0.1 -- Studs the target's own target moves a run, so it always has a record to send
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

-- The viewers each run leaves: one of the three others on three runs in four, and none on the fourth, when all three
-- were left in the three runs before
local LEFT: { number } = { 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0 }

-- Runs the watched target's runs and gives why it went wrong, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local clients: { any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 10, 0, 0)
		table.insert(clients, client)
	end

	-- The last in the list, which the first run's order would leave
	local target: any = clients[VIEWERS]
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, target)

	local seen: number = harness:spawn("Player", vector.create(0, 0, -60))
	Harness.Relay.setBudget(0)

	for run: number = 1, RUNS do
		harness.states[seen].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		harness:run()

		if #harness.passed ~= LEFT[run] then
			return `Run {run} left {#harness.passed} viewers, not {LEFT[run]}`
		end

		for _, call: any in harness.passed do
			if call.key == target.viewer.key then
				return `Run {run} left the watched target`
			end
		end

		local copied: number = 0
		for _, keys: { any } in harness.sends do
			if keys[1] == target.viewer.key then
				if keys[2] ~= moderator.viewer.key then
					return `Run {run} sent the target a block its moderator was not given`
				end

				copied += 1
			end
		end

		if copied == 0 or #moderator.seen.sizes ~= copied then
			return `Run {run} sent the target {copied} blocks and its moderator {#moderator.seen.sizes}`
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
