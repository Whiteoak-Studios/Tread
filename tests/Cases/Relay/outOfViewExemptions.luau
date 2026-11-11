--[[
    The out-of-view rate holds back only players: a recent shooter behind
    the viewer keeps its rate, an NPC keeps its own, a viewer with no body
    has no cone whether or not it has a look, and one with a body and no
    look yet has its cone along the body's facing
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40
local RELAY: number = 20 -- The example's relay rate
local RATE: number = 5 -- Hz, the out-of-view rate the case sets
local CONE: number = 60
local RADIUS: number = 15
local STRIDE: number = 0.1
local AHEAD: vector = vector.create(0, 0, -1) -- The look, and the facing of a body at a facing of 0
local EVERY: number = RUNS -- A near player or NPC's records: the reveal's, then one each run
local LOWERED: number = 1 + (RUNS - 1) // (RELAY / RATE) -- The reveal's, then one each fourth run

-- A harness whose viewer, with a body at the origin or none, holds the out-of-view rate
local function start(Harness: any, body: boolean, look: vector?): (any, any)
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.tiers.outOfView = { rate = RATE, cone = CONE, radius = RADIUS }
	end)

	local client: any = harness:viewer("Viewer")
	if body then
		client.viewer.slot = harness:spawn("Player", vector.zero)
	end

	client.viewer.look = look

	return harness, client
end

-- Each slot's records over the runs, each slot moving every run so each changes
local function count(
	Harness: any,
	harness: any,
	client: any,
	slots: { number },
	before: (() -> ())?
): { [number]: number }
	local counts: { [number]: number } = {}

	for run: number = 1, RUNS do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		-- After the first run, which makes the viewer's view
		if run == 1 and before then
			before()
		end

		for _, slot: number in slots do
			counts[slot] = (counts[slot] or 0) + Harness.count(client.seen.records, slot)
		end
	end

	return counts
end

return function (): (boolean, string | nil)
	-- A shooter far behind the viewer goes at its tier rate raised by the shot, as with no out-of-view rate at all
	local shotCounts: { number } = {}
	for index: number, lowered: boolean in { true, false } do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(false, function (_: any, server: any)
			if lowered then
				server.tiers.outOfView = { rate = RATE, cone = CONE, radius = RADIUS }
			end
		end)

		local client: any = harness:viewer("Viewer")
		client.viewer.slot = harness:spawn("Player", vector.zero)
		client.viewer.look = AHEAD

		local shooter: number = harness:spawn("Player", vector.create(0, 0, 500))
		local counts: { [number]: number } = count(Harness, harness, client, { shooter }, function ()
			Harness.Relay.shotNear(client.viewer.key, shooter)
		end)

		shotCounts[index] = counts[shooter]
	end

	if shotCounts[1] ~= shotCounts[2] then
		return false,
			`A shooter behind got {shotCounts[1]} records with the out-of-view rate and {shotCounts[2]} without`
	elseif shotCounts[1] <= LOWERED then
		return false, `A shooter behind got {shotCounts[1]} records, no more than the out-of-view rate's {LOWERED}`
	end

	-- An NPC behind keeps its own rate beside a player held back at the same distance
	local Harness: any = Environment.load(HARNESS)
	local harness: any, client: any = start(Harness, true, AHEAD)
	local npc: number = harness:spawn("Npc", vector.create(0, 0, 100))
	local player: number = harness:spawn("Player", vector.create(5, 0, 100))

	local counts: { [number]: number } = count(Harness, harness, client, { npc, player })
	if counts[npc] ~= EVERY then
		return false, `An NPC behind the viewer got {counts[npc]} records in {RUNS} runs, not {EVERY}`
	elseif counts[player] ~= LOWERED then
		return false, `A player behind the viewer got {counts[player]} records in {RUNS} runs, not {LOWERED}`
	end

	-- A viewer with no body has no cone, with no look and with one
	for _, looking: boolean in { false, true } do
		local look: vector? = nil
		if looking then
			look = AHEAD
		end

		Harness = Environment.load(HARNESS)
		harness, client = start(Harness, false, look)

		local behind: number = harness:spawn("Player", vector.create(0, 0, 100))
		counts = count(Harness, harness, client, { behind })
		if counts[behind] ~= EVERY then
			local given: string = looking and "a look" or "no look"
			return false, `With no body and {given}, a player behind got {counts[behind]} records, not {EVERY}`
		end
	end

	-- With a body and no look yet, the cone looks along the body's facing, -Z at a facing of 0
	Harness = Environment.load(HARNESS)
	harness, client = start(Harness, true, nil)

	local ahead: number = harness:spawn("Player", vector.create(0, 0, -100))
	local behind: number = harness:spawn("Player", vector.create(0, 0, 100))
	counts = count(Harness, harness, client, { ahead, behind })
	if counts[ahead] ~= EVERY or counts[behind] ~= LOWERED then
		local seen: string = `{counts[ahead]} and {counts[behind]}`
		return false, `With no look, players ahead of and behind the body got {seen} records, not {EVERY} and {LOWERED}`
	end

	return true, nil
end
