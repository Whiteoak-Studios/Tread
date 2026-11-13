--[[
    When a viewer's acknowledgments stall, its changes stay measured from
    the last record it acknowledged, 1 to 31 relay ticks back, then go whole
    once that record is 32 back, and turn back into changes once it resumes
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local DEPTH: number = 32 -- Relay ticks of records a client keeps, so a baseline is at most 31 back
local STALL: number = 1000 -- Runs an acknowledgment takes once it stalls, longer than the case runs
local WHOLE_RUNS: number = 3 -- Runs it checks go whole past the oldest baseline
local STEP: vector = vector.create(0.5, 0, 0) -- What the target walks a run, so it has a record every run

-- The target's one record of the run, as the client read it: whether it came as a change, and its base
local function readOf(Harness: any, client: any, slot: number): (number, any)
	return Harness.count(client.seen.records, slot), Harness.find(client.seen.changes, slot)
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]

	-- The reveal and one change, both acknowledged, so the change of run 2 is the baseline from here
	harness:runs(2)
	client.lag = STALL

	for back: number = 1, DEPTH - 1 do
		state.position += STEP
		harness:run()

		local records: number, change: any = readOf(Harness, client, slot)
		if records ~= 1 or not change then
			return false, `With the baseline {back} ticks back the record went whole or not at all`
		elseif change.base ~= back then
			return false, `With the baseline {back} ticks back the change named {change.base}`
		end
	end

	for run: number = 1, WHOLE_RUNS do
		state.position += STEP
		harness:run()

		local records: number, change: any = readOf(Harness, client, slot)
		if records ~= 1 or change then
			return false, `{DEPTH - 1 + run} ticks past the last acknowledgment the record did not go whole`
		end
	end

	-- Acknowledgments resume: the run they arrive at still goes whole, and the one after goes as a change of 1 back
	client.lag = 0
	table.clear(client.sent)
	harness:runs(2)

	local records: number, change: any = readOf(Harness, client, slot)
	if records ~= 1 or not change or change.base ~= 1 then
		return false, "Once acknowledgments resumed the record did not go back to a change of the newest"
	end

	return true, nil
end
