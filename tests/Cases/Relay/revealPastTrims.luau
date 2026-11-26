--[[
    A hidden player's revealed past stops at a new life in its slot, a
    teleport's epoch change, a run it was absent from the states and its
    wake from sleep; and no past rides with a reveal entering relevancy,
    after Invisible, of a sleeper, a body or an NPC, or one revealAll made
    afresh, while a pending reveal revealAll makes again keeps its past
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local RECORD_BYTES: number = 16 -- Constants.RECORD_BYTES
local PLACE: vector = vector.create(100, 0, 0)
local FAR: vector = vector.create(2000, 0, 0) -- Past the example's relevancy.leave of 1000
local STRIDE: vector = vector.create(0, 0, 0.5) -- What each body walks a run, so no two runs' records match
local TELEPORT: vector = vector.create(0, 0, 50)
local WIDE: number = 250 -- Milliseconds, whose 6 records reach past each trim's 2
local NARROW: number = 100 -- Milliseconds, whose 3 records a hidden player's reveal carries
local HIDDEN_RUNS: number = 8 -- Runs each body is hidden before the change it is trimmed at
local AFTER: number = 2 -- Runs between that change and the reveal, so the past holds these two
local PENDING_LAG: number = 2 -- Runs an acknowledgment takes, so a reveal is still pending a run on

type Scene = {
	Harness: any,
	harness: any,
	client: any,
	raws: { [number]: { [number]: string } }, -- Each slot's record as each relay tick's run encoded it
}

local function scene(delay: number, lag: number): Scene
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay = { changes = true, past = true }
	end)

	local client: any = harness:viewer("Viewer")
	client.viewer.delay = delay
	client.lag = lag

	return { Harness = Harness, harness = harness, client = client, raws = {} }
end

-- One run with every body a stride on, keeping each one's record
local function walk(s: Scene)
	for _, state: any in s.harness.states do
		state.position += STRIDE
	end

	s.harness:run()

	local records: buffer = s.Harness.Turn.world.records
	local kept: { [number]: string } = {}
	for slot: number in s.harness.states do
		kept[slot] = buffer.readstring(records, slot * RECORD_BYTES, RECORD_BYTES)
	end

	s.raws[s.harness.tick] = kept
end

-- Why this run's one reveal of a slot doesn't carry these ages with each run's record, or nil
local function carries(s: Scene, slot: number, ages: { number }, what: string): string?
	local seen: any = s.client.seen
	if s.Harness.count(seen.reveals, slot) ~= 1 then
		return `{what}: {s.Harness.count(seen.reveals, slot)} reveals came, not 1`
	end

	local past: any = s.Harness.find(seen.pasts, slot)
	if table.concat(past.ages, ",") ~= table.concat(ages, ",") then
		return `{what}: the reveal carried records aged {table.concat(past.ages, ",")}, not {table.concat(ages, ",")}`
	end

	local tick: number = s.harness.tick
	for index: number, age: number in ages do
		if past.raws[index] ~= s.raws[tick - age][slot] then
			return `{what}: the record aged {age} isn't the one relay tick {tick - age} encoded`
		end
	end

	return nil
end

--[[
    A player hidden for HIDDEN_RUNS, changed by change before the next run,
    then hidden AFTER runs more and revealed, which carries those runs alone
--]]

local function trimmed(what: string, kind: string, change: (s: Scene, slot: number) -> number): string?
	local s: Scene = scene(WIDE, 0)
	local slot: number = s.harness:spawn(kind, PLACE)
	s.harness:hide(s.client, slot, true)

	for _ = 1, HIDDEN_RUNS do
		walk(s)
	end

	slot = change(s, slot)
	for _ = 1, AFTER do
		walk(s)
	end

	s.harness:hide(s.client, slot, false)
	walk(s)

	return carries(s, slot, { 2, 1 }, what)
end

-- A new life in the same slot: every never-used slot taken, so the freed one comes back next
local function newLife(s: Scene, slot: number): number
	local slots: number = Environment.load(CONSTANTS).SLOTS
	local Slots: any = s.Harness.Slots

	s.harness:despawn(slot)
	for _ = 1, slots - Slots.count("Player") - 1 do
		Slots.take("Player")
	end

	local again: number = s.harness:spawn("Player", PLACE)
	if again ~= slot then
		error(`The new life took slot {again}, not the freed {slot}`)
	end

	return again
end

-- A teleport, which moves the body on and its epoch with it
local function teleport(s: Scene, slot: number): number
	local state: any = s.harness.states[slot]
	state.position += TELEPORT
	state.epoch = (state.epoch + 1) % 256

	return slot
end

-- One run with the body out of the states, its slot kept
local function absent(s: Scene, slot: number): number
	local state: any = s.harness.states[slot]
	s.harness.states[slot] = nil
	walk(s)
	s.harness.states[slot] = state

	return slot
end

local function wake(s: Scene, slot: number): number
	s.Harness.Slots.setEntry(slot, { kind = "Player", rig = "A" })

	return slot
end

-- The reveals of a run whose past isn't empty, as a list of the slots, or nil when none is
local function withPast(s: Scene): string?
	local slots: { string } = {}
	for _, past: any in s.client.seen.pasts do
		if #past.ages ~= 0 then
			table.insert(slots, `{past.slot}`)
		end
	end

	return #slots > 0 and table.concat(slots, ",") or nil
end

return function (): (boolean, string | nil)
	local problem: string? = trimmed("After a new life", "Player", newLife)
		or trimmed("After a teleport", "Player", teleport)
		or trimmed("After a run out of the states", "Player", absent)
		or trimmed("After waking", "Sleeper", wake)
	if problem then
		return false, problem
	end

	-- Every body hidden but the one entering relevancy, and the one revealAll makes afresh, sent from the first run
	local s: Scene = scene(NARROW, 0)
	local harness: any = s.harness
	local entering: number = harness:spawn("Player", FAR)
	local invisible: number = harness:spawn("Player", PLACE)
	local sleeper: number = harness:spawn("Sleeper", PLACE)
	local body: number = harness:spawn("Body", PLACE)
	local npc: number = harness:spawn("Npc", PLACE)
	local hidden: number = harness:spawn("Player", PLACE)
	local sent: number = harness:spawn("Player", PLACE)

	for _, slot: number in { invisible, sleeper, body, npc, hidden } do
		harness:hide(s.client, slot, true)
	end

	for _ = 1, HIDDEN_RUNS do
		walk(s)
	end

	-- In one run: the far player comes into range, the hidden player, sleeper, body and NPC are shown, and the
	-- player hidden to the run before turns Invisible as it is shown
	harness.states[entering].position = PLACE
	for _, slot: number in { invisible, sleeper, body, npc, hidden } do
		harness:hide(s.client, slot, false)
	end

	s.Harness.Relay.setInvisible(invisible, true)
	walk(s)

	problem = carries(s, hidden, { 3, 2, 1 }, "The hidden player beside the rest")
	if problem then
		return false, problem
	end

	for _, slot: number in { entering, sleeper, body, npc } do
		if s.Harness.count(s.client.seen.reveals, slot) ~= 1 then
			return false, `Slot {slot} came {s.Harness.count(s.client.seen.reveals, slot)} times, not revealed once`
		end
	end

	local carried: string? = withPast(s)
	if carried ~= tostring(hidden) then
		return false, `The reveals of slots {carried} carried a past, not the hidden player's alone`
	end

	s.Harness.Relay.setInvisible(invisible, false)
	walk(s)
	if s.Harness.count(s.client.seen.reveals, invisible) ~= 1 then
		return false, "The player back from Invisible was not revealed"
	end

	carried = withPast(s)
	if carried then
		return false, `The reveals of slots {carried} carried a past after Invisible`
	end

	-- revealAll makes a reveal of every player sent, none of them pending
	s.Harness.Relay.revealAll(s.client.viewer.key)
	walk(s)
	if s.Harness.count(s.client.seen.reveals, sent) ~= 1 then
		return false, "revealAll made no reveal of the player sent all along"
	end

	carried = withPast(s)
	if carried then
		return false, `The reveals revealAll made of slots {carried} carried a past`
	end

	-- A pending reveal revealAll makes again carries its past again
	local pending: Scene = scene(NARROW, PENDING_LAG)
	local player: number = pending.harness:spawn("Player", PLACE)
	pending.harness:hide(pending.client, player, true)
	for _ = 1, HIDDEN_RUNS do
		walk(pending)
	end

	pending.harness:hide(pending.client, player, false)
	walk(pending)
	pending.Harness.Relay.revealAll(pending.client.viewer.key)
	walk(pending)

	problem = carries(pending, player, { 3, 2, 1 }, "The pending reveal revealAll made again")
	if problem then
		return false, problem
	end

	return true, nil
end
