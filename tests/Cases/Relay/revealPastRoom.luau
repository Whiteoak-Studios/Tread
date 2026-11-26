--[[
    A hidden player's reveal carries its past only while the viewer's soft
    room holds it, going bare in the hard room when only that is left and
    carrying it again on a repeat with room; a wall falling on 40 hidden
    players sends every past inside the soft room at 100 ms, and at 250 ms
    the past rides until that room runs out and the rest go bare
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLACE: vector = vector.create(100, 0, 0)
local HIDDEN_RUNS: number = 8
local SOFT: number = 64000 -- The example's budget.soft of 64 KB/s, in bytes a second
local RELAY_RATE: number = 20 -- The example's rates.relay
local FRAME_BYTES: number = 3 -- Volt's framing of each block, which the room counts
local CROWD: number = 40 -- Players behind the wall
local GAP: number = 3 -- Studs between them along the wall, all inside the first band

-- Volt's count for a viewer whose soft room, 50 B, is less than a block holding a reveal and its past, while its hard
-- room, the hard budget's 4,800 B a run, holds the bare reveal
local SOFT_SPENT: number = SOFT - 50

-- At 250 ms each reveal with its 6 records takes 125 B, 7 to a block, and bare 23 B. Three full blocks of 7, 887 B
-- each with framing, and 4 in a fourth put 25 inside the soft room's 3,200 B a run, in 3,173 B; the 26th would pass
-- it, so it and the 14 after it go bare in the fourth block, 3,518 B in all, inside the hard room's 4,800
local WIDE_CARRIED: number = 25

type Scene = {
	Harness: any,
	harness: any,
	client: any,
	slots: { number },
}

-- A harness with relay.past and a viewer of a delay, and count players anti-ESP hides from it for HIDDEN_RUNS
local function scene(delay: number, count: number, lag: number): Scene
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay = { changes = true, past = true }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.delay = delay
	client.lag = lag

	local slots: { number } = {}
	for index: number = 1, count do
		local slot: number = harness:spawn("Player", PLACE + vector.create(0, 0, index * GAP))
		harness:hide(client, slot, true)
		table.insert(slots, slot)
	end

	harness:runs(HIDDEN_RUNS)
	for _, slot: number in slots do
		harness:hide(client, slot, false)
	end

	return { Harness = Harness, harness = harness, client = client, slots = slots }
end

-- How many of the run's reveals carried records, and how many of those carried a count other than count
local function carried(s: Scene, count: number): (number, number)
	local with: number, other: number = 0, 0
	for _, past: any in s.client.seen.pasts do
		if #past.ages ~= 0 then
			with += 1
			if #past.ages ~= count then
				other += 1
			end
		end
	end

	return with, other
end

-- The bytes the run's blocks took with Volt's framing
local function spent(s: Scene): number
	local total: number = 0
	for _, size: number in s.client.seen.sizes do
		total += size + FRAME_BYTES
	end

	return total
end

return function (): (boolean, string | nil)
	-- With only the hard room the reveal goes bare, and its repeat with soft room again carries its past
	local s: Scene = scene(100, 1, 1)
	s.harness.traffic = SOFT_SPENT
	s.harness:run()

	local with: number = carried(s, 3)
	if s.Harness.count(s.client.seen.reveals, s.slots[1]) ~= 1 then
		return false, "With only the hard room, the hidden player was not revealed"
	elseif with ~= 0 then
		return false, "With only the hard room, the reveal still carried its past"
	end

	s.harness.traffic = 0
	s.harness:run()

	local other: number
	with, other = carried(s, 3)
	if s.Harness.count(s.client.seen.reveals, s.slots[1]) ~= 1 or with ~= 1 or other ~= 0 then
		return false, "The repeat with the soft room back did not carry the 3 records"
	end

	-- The wall falls at 100 ms: every reveal carries its 3 records, inside the soft room
	s = scene(100, CROWD, 0)
	s.harness:run()

	with, other = carried(s, 3)
	if #s.client.seen.reveals ~= CROWD or with ~= CROWD or other ~= 0 then
		return false, `At 100 ms, {with} of {#s.client.seen.reveals} reveals carried 3 records, not all {CROWD}`
	elseif spent(s) > SOFT / RELAY_RATE then
		return false, `At 100 ms, the burst took {spent(s)} B, past the soft room's {SOFT / RELAY_RATE}`
	end

	-- And at 250 ms the soft room runs out first
	s = scene(250, CROWD, 0)
	s.harness:run()

	with, other = carried(s, 6)
	if #s.client.seen.reveals ~= CROWD then
		return false, `At 250 ms, {#s.client.seen.reveals} of the {CROWD} hidden players were revealed`
	elseif with ~= WIDE_CARRIED or other ~= 0 then
		return false, `At 250 ms, {with} reveals carried records, {other} not 6 of them, not {WIDE_CARRIED} with 6`
	end

	return true, nil
end
