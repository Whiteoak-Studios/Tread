--[[
    Sleepers and NPCs past their kind's reach are not gathered: a seeded
    layout with no body between that reach and relevancy.leave sends the
    same at each kind's reach as at relevancy.leave, gathering fewer bodies
--]]

--!strict
local serde = require("@lune/serde")

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807
local SEED: number = 505
local RUNS: number = 30
local KEYFRAMES: number = 10 -- Every this many runs each viewer's keyframe joins the digest
local NEAR: number = 250 -- A phone's render distance, which every fourth viewer sets
local NEAR_EVERY: number = 4
local WHOLE: number = 1000 -- The example's relevancy.leave, the reach every kind is gathered to in the second arm

-- The viewers stand in a square and scuffle in it, a share of their pairs hidden
local CENTER: vector = vector.create(1000, 0, -600)
local VIEWERS: number = 24
local SPREAD: number = 120
local STEP: number = 0.5 -- Studs a body may move along each axis a run
local TURN: number = 0.3 -- Radians a body may turn either way a run
local HIDDEN: number = 0.2
local SLEEPERS_HIDDEN: number = 0.1

-- Every other body stands close, inside 500 studs of every viewer, or far, past 1,000, so no pair falls between a
-- kind's own reach and relevancy.leave and both arms send the same; the far ones lie in cells relevancy.leave spans
local CLOSE: number = 380 -- The side of the square the close ones stand in
local FAR_FROM: number = 1250 -- Studs from the center the far ones stand
local FAR_TO: number = 3000
local CLOSE_SLEEPERS: number = 40
local FAR_SLEEPERS: number = 300
local CLOSE_NPCS: number = 6
local FAR_NPCS: number = 12
local BODIES: number = 3

-- Some close sleepers go far and as many far ones come close, some go and as many come, and some NPCs go far, so
-- pairs that leave their kind's cells get their hides from the tracked list
local TELEPORT_RUN: number = 10
local TELEPORTED: number = 5
local SWAP_RUN: number = 15
local SWAPPED: number = 3
local NPC_RUN: number = 20
local NPCS_MOVED: number = 2

-- The digest both arms give, which changes only with what a viewer is sent, and the bodies each arm's turns gather
local EXPECTED: string = "8a432223525a67e538e15260d10b8594096ed7c079cb62d620f66f35e54aeb21"
local OWN_VISITS: number = 52894
local WHOLE_VISITS: number = 66934

type Generator = () -> number

-- What one arm's runs gave
type Arm = {
	digest: string,
	reveals: number,
	hides: number,
	visits: number,
	left: number, -- The pairs drawn as the moves took their bodies far
	stale: number, -- And those still drawn once each move's run was read
}

-- A seeded generator of numbers between 0 and 1
local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

-- A place in a square of a side around the center, on the ground
local function within(random: Generator, side: number): vector
	return CENTER + vector.create((random() - 0.5) * side, 0, (random() - 0.5) * side)
end

-- A place on the ground between FAR_FROM and FAR_TO from the center
local function afar(random: Generator): vector
	local angle: number = random() * 2 * math.pi
	local length: number = FAR_FROM + random() * (FAR_TO - FAR_FROM)

	return CENTER + vector.create(math.cos(angle) * length, 0, math.sin(angle) * length)
end

-- The pairs the clients draw of the slots listed
local function drawn(clients: { any }, slots: { number }): number
	local count: number = 0

	for _, client: any in clients do
		for _, slot: number in slots do
			if client.drawn[slot] then
				count += 1
			end
		end
	end

	return count
end

--[[
    One arm: the layout's runs on the example's tables, with sleepers.radius
    and npcs.range at reach when given, every block, keyframe and the
    relay's counts in the digest
--]]

local function arm(reach: number?): Arm
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(false, function (_: any, server: any)
		if reach then
			server.sleepers.radius = reach
			server.npcs.range = reach
		end
	end)

	local random: Generator = generator(SEED)
	local parts: { string } = {}
	local names: { [any]: string } = {}
	local clients: { any } = {}
	local result: Arm = { digest = "", reveals = 0, hides = 0, visits = 0, left = 0, stale = 0 }

	local function label(keys: { any }): string
		local list: { string } = {}
		for index: number, key: any in keys do
			list[index] = names[key]
		end

		return table.concat(list, ",")
	end

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		table.insert(parts, `block {label(keys)} {buffer.len(data)} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
	end

	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		names[client.viewer.key] = `Viewer{index}`
		table.insert(clients, client)

		local at: vector = within(random, SPREAD)
		client.viewer.position = at
		client.viewer.slot = harness:spawn("Player", at)
		harness.states[client.viewer.slot].facing = random() * 2 * math.pi

		if index % NEAR_EVERY == 0 then
			Harness.Relay.setDistance(client.viewer.key, NEAR)
		end
	end

	local close: { number } = {}
	for _ = 1, CLOSE_SLEEPERS do
		table.insert(close, harness:spawn("Sleeper", within(random, CLOSE)))
	end

	local far: { number } = {}
	for _ = 1, FAR_SLEEPERS do
		table.insert(far, harness:spawn("Sleeper", afar(random)))
	end

	local npcs: { number } = {}
	for _ = 1, CLOSE_NPCS do
		table.insert(npcs, harness:spawn("Npc", within(random, CLOSE)))
	end

	for _ = 1, FAR_NPCS do
		harness:spawn("Npc", afar(random))
	end

	for _ = 1, BODIES do
		harness:spawn("Body", within(random, CLOSE))
	end

	for _, client: any in clients do
		for _, other: any in clients do
			if other ~= client then
				harness:hide(client, other.viewer.slot, random() < HIDDEN)
			end
		end

		for _, slot: number in close do
			harness:hide(client, slot, random() < SLEEPERS_HIDDEN)
		end
	end

	for run: number = 1, RUNS do
		for _, client: any in clients do
			local state: any = harness.states[client.viewer.slot]
			state.position += vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
			state.facing += (random() - 0.5) * 2 * TURN
			client.viewer.position = state.position
			client.viewer.look = vector.create(-math.sin(state.facing), 0, -math.cos(state.facing))
		end

		local moved: { number } = {}
		if run == TELEPORT_RUN then
			for index: number = 1, TELEPORTED do
				harness.states[close[index]].position = afar(random)
				harness.states[far[index]].position = within(random, CLOSE)
				table.insert(moved, close[index])
			end
		elseif run == SWAP_RUN then
			for index: number = TELEPORTED + 1, TELEPORTED + SWAPPED do
				harness:despawn(close[index])
				harness:spawn("Sleeper", within(random, CLOSE))
			end
		elseif run == NPC_RUN then
			for index: number = 1, NPCS_MOVED do
				harness.states[npcs[index]].position = afar(random)
				table.insert(moved, npcs[index])
			end
		end

		result.left += drawn(clients, moved)
		harness:run()
		result.stale += drawn(clients, moved)

		for _, client: any in clients do
			result.reveals += #client.seen.reveals
			result.hides += #client.seen.hides
		end

		if run % KEYFRAMES == 0 then
			for _, client: any in clients do
				local keyframe: buffer = Harness.Relay.keyframe(client.viewer.key)
				table.insert(parts, `keyframe {names[client.viewer.key]} {buffer.tostring(keyframe)}`)
			end
		end
	end

	local sent: number, cut: number, visits: number = Harness.Relay.counts()
	table.insert(parts, `counts {sent} {cut}`)
	result.digest = serde.hash("sha256", table.concat(parts, "\n"))
	result.visits = visits

	return result
end

return function (): (boolean, string | nil)
	local own: Arm = arm(nil)
	local whole: Arm = arm(WHOLE)

	-- The layout reaches what it is for, so its digest pins it
	if own.reveals == 0 or own.hides == 0 then
		return false, "The layout revealed nothing or hid nothing"
	elseif own.left == 0 then
		return false, "The moves took no body a client draws far"
	elseif own.stale ~= 0 then
		return false, `{own.stale} of the {own.left} pairs the moves took far were still drawn after their runs`
	end

	for name: string, result: Arm in { own = own, whole = whole } do
		if result.digest ~= EXPECTED then
			return false, `The {name} arm's blocks and keyframes digest to {result.digest}, not {EXPECTED}`
		end
	end

	if own.visits ~= OWN_VISITS or whole.visits ~= WHOLE_VISITS then
		return false,
			`The turns gathered {own.visits} bodies at each kind's reach and {whole.visits} at relevancy.leave, not {OWN_VISITS} and {WHOLE_VISITS}`
	elseif own.visits >= whole.visits then
		return false,
			`Each kind's own reach gathered {own.visits} bodies, no fewer than relevancy.leave's {whole.visits}`
	end

	return true, nil
end
