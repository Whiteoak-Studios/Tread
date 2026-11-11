--[[
    Changes give the client exactly what whole records give it: the same
    moving targets relayed with relay.changes on, through 30% block loss and
    acknowledgments 3 runs late, decode byte for byte to the records the
    relay sends with it off
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TARGETS: number = 20
local RUNS: number = 200
local LAG: number = 3 -- Runs each acknowledgment of the client with changes on takes to reach the relay
local SETTLE: number = 5 -- Runs before any loss, so both harnesses' reveals are acknowledged alike
local LOSS_SPREAD: number = 7 -- Steps the loss pattern takes through each ten runs, so the losses scatter
local LOSS_TENTHS: number = 3 -- Of each ten runs, those whose first block is lost: 30%
local TENTHS: number = 10
local RING: number = 30 -- Studs each target's circle spans
local WALK: number = 0.04 -- Radians round its circle a target walks a run
local HOP_EVERY: number = 23 -- Runs between a target's hops, which take Y past what a step of it holds
local HOP: number = 6 -- Studs
local CLIMB: number = 0.05 -- Studs Y climbs a run between hops, which a step of it holds
local TURN: number = 0.03 -- Radians each target's facing turns a run, times its place in the list
local SPRINT_EVERY: number = 5 -- Runs between a target's sprints, each a run long, so the state word changes
local LEANS: number = 9 -- Lean levels a target sways through
local LEAN_STEP: number = 2 -- Degrees between them

-- Sets each target's state for a run, the same in both harnesses
local function move(harness: any, slots: { number }, run: number)
	for index: number, slot: number in slots do
		local state: any = harness.states[slot]
		local angle: number = index + run * WALK
		local height: number = (run % HOP_EVERY) * CLIMB
		if (run + index) % HOP_EVERY == 0 then
			height += HOP
		end

		state.position = vector.create(math.cos(angle) * RING, height, math.sin(angle) * RING)
		state.facing = (run * TURN * index) % (2 * math.pi)
		state.sprint = (run + index) % SPRINT_EVERY == 0
		state.lean = ((run + index) % LEANS - LEANS // 2) * LEAN_STEP
	end
end

-- A harness with the targets in it and its client, relay.changes as given
local function build(changes: boolean): (any, any, { number })
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay.changes = changes
	end)

	local client: any = harness:viewer("Viewer")
	local slots: { number } = {}
	for _ = 1, TARGETS do
		table.insert(slots, harness:spawn("Player", vector.zero))
	end

	return harness, client, slots
end

return function (): (boolean, string | nil)
	local whole: any, wholeClient: any, slots: { number } = build(false)
	local changing: any, client: any, changingSlots: { number } = build(true)

	if table.concat(slots, ",") ~= table.concat(changingSlots, ",") then
		return false, "The two harnesses put the targets in different slots"
	end

	local decoded: number, changes: number = 0, 0

	for run: number = 1, RUNS do
		move(whole, slots, run)
		move(changing, slots, run)

		if run > SETTLE and (run * LOSS_SPREAD) % TENTHS < LOSS_TENTHS then
			client.lose = 1
		end

		if run == SETTLE then
			client.lag = LAG
		end

		whole:run()
		changing:run()

		-- What the relay sent with changes off this run, by slot, which its client lost none of
		local sent: { [number]: string } = {}
		for index: number, record: any in wholeClient.seen.records do
			sent[record.slot] = wholeClient.seen.raws[index]
		end

		for index: number, record: any in client.seen.records do
			if client.seen.raws[index] ~= sent[record.slot] then
				return false, `On run {run} slot {record.slot} decoded to other bytes than the whole record sent`
			end
		end

		decoded += #client.seen.records
		changes += #client.seen.changes
	end

	if changes < decoded / 2 then
		return false, `Only {changes} of the {decoded} records decoded came as changes`
	end

	return true, nil
end
