--[[
    With relay.past, a player anti-ESP hid the run before is revealed with
    its last records, 3 at 100 ms, 6 at 250, 3 at 0 and 6 at 400, each its
    run's record byte for byte, aged in relay ticks across a skipped one,
    and carried afresh on each repeat until the reveal is acknowledged
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RECORD_BYTES: number = 16 -- Constants.RECORD_BYTES
local PLACE: vector = vector.create(100, 0, 0)
local STRIDE: vector = vector.create(0, 0, 0.5) -- What the player walks a run, so no two runs' records match
local HIDDEN_RUNS: number = 10 -- Runs it is hidden before its reveal, past the 7 records a reveal can carry
local LAG: number = 2 -- Runs an acknowledgment takes to arrive, so the reveal rides this many repeats after its first

-- Each delay in milliseconds and the records its reveal carries at the example's 20 Hz relay: the delay held to
-- rewind's 0.10 to 0.25 s, times 20, rounded up, plus 1
local DELAYS: { { delay: number, count: number } } = {
	{ delay = 100, count = 3 },
	{ delay = 250, count = 6 },
	{ delay = 0, count = 3 },
	{ delay = 400, count = 6 },
}

-- With the relay tick two before the reveal's skipped, each delay's ages, oldest first: through the first at least
-- the count above old
local SKIPPED: { { delay: number, ages: { number } } } = {
	{ delay = 100, ages = { 3, 1 } },
	{ delay = 250, ages = { 6, 5, 4, 3, 1 } },
}

type Scene = {
	Harness: any,
	harness: any,
	client: any,
	slot: number,
	raws: { [number]: string }, -- The player's record as each relay tick's run encoded it
}

-- A harness with relay.past, a viewer of a delay whose acknowledgments take lag runs, and a player anti-ESP hides
local function scene(delay: number, lag: number): Scene
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay = { changes = true, past = true }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.delay = delay
	client.lag = lag

	local slot: number = harness:spawn("Player", PLACE)
	harness:hide(client, slot, true)

	return { Harness = Harness, harness = harness, client = client, slot = slot, raws = {} }
end

-- One run with the player a stride on, keeping the record it encoded
local function walk(s: Scene)
	s.harness.states[s.slot].position += STRIDE
	s.harness:run()
	s.raws[s.harness.tick] = buffer.readstring(s.Harness.Turn.world.records, s.slot * RECORD_BYTES, RECORD_BYTES)
end

-- Why the run's one reveal of the player doesn't carry exactly these ages with each run's record, or nil
local function carries(s: Scene, ages: { number }, what: string): string?
	local seen: any = s.client.seen
	if s.Harness.count(seen.reveals, s.slot) ~= 1 then
		return `{what}: {s.Harness.count(seen.reveals, s.slot)} reveals of the player came, not 1`
	end

	local past: any = s.Harness.find(seen.pasts, s.slot)
	local tick: number = s.harness.tick
	if table.concat(past.ages, ",") ~= table.concat(ages, ",") then
		return `{what}: the reveal carried records aged {table.concat(past.ages, ",")}, not {table.concat(ages, ",")}`
	end

	for index: number, age: number in ages do
		if past.raws[index] ~= s.raws[tick - age] then
			return `{what}: the record aged {age} isn't the one relay tick {tick - age} encoded`
		end
	end

	local own: number = table.find(seen.raws, s.raws[tick]) or 0
	if own == 0 then
		return `{what}: the reveal's own record isn't this run's`
	end

	return nil
end

-- Ages from count down to 1, oldest first
local function falling(count: number): { number }
	local ages: { number } = {}
	for index: number = 1, count do
		ages[index] = count - index + 1
	end

	return ages
end

return function (): (boolean, string | nil)
	for _, entry: { delay: number, count: number } in DELAYS do
		local s: Scene = scene(entry.delay, LAG)
		local at: string = `At {entry.delay} ms`

		for _ = 1, HIDDEN_RUNS do
			walk(s)
			if s.Harness.count(s.client.seen.reveals, s.slot) ~= 0 then
				return false, `{at}, the hidden player was revealed`
			end
		end

		-- The reveal and each repeat before its acknowledgment arrives, each with the records before its own run
		s.harness:hide(s.client, s.slot, false)
		for run: number = 0, LAG do
			walk(s)

			local problem: string? = carries(s, falling(entry.count), `{at}, run {run} of the reveal`)
			if problem then
				return false, problem
			end
		end

		walk(s)
		if s.Harness.count(s.client.seen.reveals, s.slot) ~= 0 then
			return false, `{at}, the reveal rode on once its acknowledgment arrived`
		end
	end

	for _, entry: { delay: number, ages: { number } } in SKIPPED do
		local s: Scene = scene(entry.delay, 0)

		for run: number = 1, HIDDEN_RUNS do
			if run == HIDDEN_RUNS then
				s.harness.tick += 1
			end

			walk(s)
		end

		s.harness:hide(s.client, s.slot, false)
		walk(s)

		local problem: string? = carries(s, entry.ages, `At {entry.delay} ms across a skipped relay tick`)
		if problem then
			return false, problem
		end
	end

	return true, nil
end
