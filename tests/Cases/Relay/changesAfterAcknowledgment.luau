--[[
    With relay.changes on, a moving target's record goes whole with its
    reveal until the viewer acknowledges a block, and as its change after,
    each against the newest record acknowledged, decoding to the server's own
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local LAG: number = 2 -- Runs each acknowledgment takes to reach the relay
local RUNS: number = 10
local STEP: vector = vector.create(0.25, 0, 0.5) -- What the target walks a run, so it has a record every run
local QUANTUM: number = 1 / 64 -- Studs a record's X and Z step by

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	client.lag = LAG

	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]

	for run: number = 1, RUNS do
		state.position += STEP
		harness:run()

		local seen: any = client.seen
		local records: number = Harness.count(seen.records, slot)
		local changes: { any } = {}
		for _, change: any in seen.changes do
			if change.slot == slot then
				table.insert(changes, change)
			end
		end

		-- The block of run 1 is acknowledged on run LAG + 2, so until then the record rides whole with the reveal
		if records ~= 1 then
			return false, `Run {run} carried {records} records of the target, not 1`
		elseif run <= LAG + 1 and (#changes ~= 0 or Harness.count(seen.reveals, slot) ~= 1) then
			return false, `Run {run}, before any acknowledgment, sent no whole record with its reveal`
		elseif run > LAG + 1 and #changes ~= 1 then
			return false, `Run {run}, after the first acknowledgment, sent the record whole`
		elseif run > LAG + 1 and changes[1].base ~= LAG + 1 then
			return false, `Run {run}'s change was against {changes[1].base} ticks back, not the newest acknowledged`
		end

		local record: any = Harness.find(seen.records, slot)
		local off: vector = record.position - state.position
		if math.abs(off.x) > QUANTUM or math.abs(off.z) > QUANTUM or math.abs(off.y) > QUANTUM then
			return false, `Run {run}'s record decoded to {record.position}, not the target's {state.position}`
		end
	end

	return true, nil
end
