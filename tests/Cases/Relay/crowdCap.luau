--[[
    A crowd cap of 8 among 40 candidates keeps the 8 smallest keys at their
    band's rates, a tie to the lower slot, changes only the fills' order at
    the band's aim, and under a tight budget drops the rest to its floor
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local SETTLE: number = 6 -- Runs before the count, past every reveal and every out-of-view mark
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local STRIDE: number = 0.1 -- Studs each target moves along z a run, back and forth, so each always has a change
local SIZE: number = 8
local HALF: number = 10 -- Hz, half the first band's aim, which the rest aim for in the first run
local AIM: number = 20 -- Hz, the first band's aim
local FLOOR: number = 5 -- Hz, the cap's floor, which is the example's out-of-view rate too
local FULL: number = RUNS -- A record each run, at the first band's aim
local SHARE: number = RUNS // 2 -- At HALF
local LEAST: number = RUNS // 4 -- At FLOOR
local BAND_FLOOR: number = RUNS * 3 // 4 -- At the first band's 15 Hz floor

-- The tight budget: two members and four rest, every record whole, and a viewer whose soft room each relay tick holds
-- one block's header and framing, the two members' records and half a record more
local TIGHT_SIZE: number = 2
local TIGHT_DISTANCES: { number } = { 100, 110, 120, 130, 140, 150 } -- Studs ahead of the viewer
local SOFT_BYTES: number = 64000 -- The example's soft budget, 64 KB a second
local OPENING: number = 12 -- A block's header, 9 B, and Volt's framing, 3 B
local RECORD: number = 16
local ROOM: number = OPENING + TIGHT_SIZE * RECORD + RECORD // 2

-- One candidate: where it stands from the viewer, which faces -Z from the origin, whether it should be one of the
-- cap's members, and whether the out-of-view rate holds it past its radius behind the viewer
type Candidate = { at: vector, member: boolean, outside: boolean }

-- What one run of the candidates kept: each one's records, and each counted run's records' slots in block order
type Seen = { counts: { number }, orders: { { number } }, slots: { number } }

local SHOOTER: number = 7 -- The candidate whose bullet passed near the viewer
local TIE_LOW: number = 8 -- Two candidates the same distance off, spawned in this order, so the first has the lower slot
local TIE_HIGH: number = 9

--[[
    The 40 candidates, every one inside the first band. With the example's
    weights a key is the squared distance over 2.25 in view or inside the
    radius, over 1 out of view, and over 9 for the shooter in view, so the
    8 smallest run 400, 3,600, 4,444, 5,378, 5,625, 5,878, 6,944 and 7,511
--]]

local function candidates(): { Candidate }
	local list: { Candidate } = {
		{ at = vector.create(0, 0, 30), member = true, outside = false }, -- Behind, inside the out-of-view radius
		{ at = vector.create(0, 0, 60), member = true, outside = true },
		{ at = vector.create(0, 0, -100), member = true, outside = false },
		{ at = vector.create(0, 0, -110), member = true, outside = false },
		{ at = vector.create(0, 0, 75), member = true, outside = true },
		{ at = vector.create(0, 0, -115), member = true, outside = false },
		{ at = vector.create(0, 0, -250), member = true, outside = false }, -- The shooter, a member by its weight alone
		{ at = vector.create(-50, 0, -120), member = true, outside = false },
		{ at = vector.create(50, 0, -120), member = false, outside = false },
		{ at = vector.create(0, 0, 90), member = false, outside = true }, -- A member were the cone weighed it too
	}

	-- The rest of the crowd in a line ahead, 140 to 285 studs out
	for place: number = 0, 29 do
		table.insert(list, { at = vector.create(0, 0, -(140 + place * 5)), member = false, outside = false })
	end

	return list
end

-- The records a candidate gets over the count at a cap rate, member or not, held to the out-of-view rate or not
local function expected(entry: Candidate, rate: number): number
	if entry.outside then
		return LEAST
	elseif entry.member or rate == AIM then
		return FULL
	end

	return SHARE
end

-- Why a run's records put a fill of the rest before a member's, or nil; the out-of-view records are owed, so go first
local function misordered(seen: Seen, list: { Candidate }): string?
	local index: { [number]: number } = {}
	for place: number, slot: number in seen.slots do
		index[slot] = place
	end

	for run: number, order: { number } in seen.orders do
		local lastMember: number = 0
		local firstRest: number = math.huge
		for at: number, slot: number in order do
			local entry: Candidate = list[index[slot]]
			if entry.outside then
				continue
			elseif entry.member then
				lastMember = at
			elseif at < firstRest then
				firstRest = at
			end
		end

		if lastMember > firstRest then
			return `Counted run {run} placed a fill of the rest at {firstRest}, before a member's at {lastMember}`
		end
	end

	return nil
end

-- The candidates under the cap given, or none, with the shooter's bullet passing near the viewer after the first run
local function drive(crowd: { size: number, rate: number, floor: number }?): Seen
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, function (shared: any, server: any)
		Bands.three(shared, server)
		server.relay = { changes = false }
		server.tiers.crowd = crowd
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	-- The farthest spawned first, so each nearer one comes in past the cap's farthest member, the tie in its own order
	local list: { Candidate } = candidates()
	local spawning: { number } = {}
	for place: number = #list, 1, -1 do
		table.insert(spawning, place)
	end

	local low: number? = table.find(spawning, TIE_LOW)
	local high: number? = table.find(spawning, TIE_HIGH)
	if low and high then
		spawning[low], spawning[high] = TIE_HIGH, TIE_LOW
	end

	local seen: Seen = { counts = {}, orders = {}, slots = {} }
	for _, place: number in spawning do
		seen.slots[place] = harness:spawn("Player", list[place].at)
		seen.counts[place] = 0
	end

	for run: number = 1, SETTLE + RUNS do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in seen.slots do
			harness.states[slot].position += vector.create(0, 0, step)
		end

		harness:run()

		if run == 1 then
			Harness.Relay.shotNear(client.viewer.key, seen.slots[SHOOTER])
		elseif run > SETTLE then
			local order: { number } = {}
			for _, record: any in client.seen.records do
				table.insert(order, record.slot)
			end

			table.insert(seen.orders, order)
			for place: number, slot: number in seen.slots do
				seen.counts[place] += Harness.count(client.seen.records, slot)
			end
		end
	end

	return seen
end

-- Why a run's counts differ from what the cap's members and its rate give, or nil
local function judge(seen: Seen, list: { Candidate }, rate: number): string?
	for place: number, entry: Candidate in list do
		local want: number = expected(entry, rate)
		if seen.counts[place] ~= want then
			local where: string = `({entry.at.x}, {entry.at.z})`
			return `At {rate} Hz the candidate at {where} got {seen.counts[place]} records over {RUNS} runs, not {want}`
		end
	end

	return nil
end

--[[
    Two members and four rest under the tight budget from the first counted
    run, after a settle with room: each record a member got and each the
    rest got, or why the run went otherwise
--]]

local function tight(): ({ number }?, string?)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, function (shared: any, server: any)
		Bands.three(shared, server)
		server.relay = { changes = false }
		server.tiers.crowd = { size = TIGHT_SIZE, rate = AIM, floor = FLOOR }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	local slots: { number } = {}
	local counts: { number } = {}
	for place: number, distance: number in TIGHT_DISTANCES do
		slots[place] = harness:spawn("Player", vector.create(0, 0, -distance))
		counts[place] = 0
	end

	for run: number = 1, SETTLE + RUNS do
		if run == SETTLE + 1 then
			harness.traffic = SOFT_BYTES - ROOM
		end

		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(0, 0, step)
		end

		harness:run()

		if run > 1 and run <= SETTLE and #client.seen.records ~= #slots then
			return nil, `With room, settle run {run} sent {#client.seen.records} records, not {#slots}`
		elseif run > SETTLE then
			for place: number, slot: number in slots do
				counts[place] += Harness.count(client.seen.records, slot)
			end
		end
	end

	return counts, nil
end

return function (): (boolean, string | nil)
	local list: { Candidate } = candidates()

	-- The rest at half the first band's aim show which 8 the cap kept
	local half: Seen = drive({ size = SIZE, rate = HALF, floor = FLOOR })
	if half.slots[TIE_LOW] > half.slots[TIE_HIGH] then
		return false, "The tied candidates were spawned with the higher slot first"
	end

	local why: string? = judge(half, list, HALF) or misordered(half, list)
	if why then
		return false, why
	end

	-- At the band's aim with room every candidate gets what it does with no cap, run by run, the rest's fills last
	local open: Seen = drive({ size = SIZE, rate = AIM, floor = FLOOR })
	local plain: Seen = drive(nil)
	why = judge(open, list, AIM) or misordered(open, list) or judge(plain, list, AIM)
	if why then
		return false, why
	end

	for run: number, order: { number } in open.orders do
		local capped: { number } = table.clone(order)
		local uncapped: { number } = table.clone(plain.orders[run])
		table.sort(capped)
		table.sort(uncapped)
		if table.concat(capped, " ") ~= table.concat(uncapped, " ") then
			return false, `At the band's aim, counted run {run} sent other records with the cap than without it`
		end
	end

	-- Under the tight budget the members keep their band's rates, losing a fill only when the rest's floor is owed
	local counts: { number }?, failure: string? = tight()
	if counts == nil then
		return false, failure
	end

	for place: number, count: number in counts do
		local want: number = place <= TIGHT_SIZE and BAND_FLOOR or LEAST
		if count ~= want then
			local which: string = place <= TIGHT_SIZE and "member" or "one of the rest"
			return false, `Under the tight budget, {which} {TIGHT_DISTANCES[place]} studs out got {count}, not {want}`
		end
	end

	return true, nil
end
