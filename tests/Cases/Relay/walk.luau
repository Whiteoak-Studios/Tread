--[[
    Seeded layouts through the relay harness, idle, a fight, wide sleepers
    and tap sinks, give every block, frame and keyframe the digests pinned
--]]

--!strict
local serde = require("@lune/serde")

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807
local KEYFRAMES: number = 10 -- Every this many runs each viewer's keyframe joins the digest
local NEAR: number = 250 -- A phone's render distance, which some viewers set
local FULL: number = 1000 -- The example's relevancy.leave, every other viewer's distance

-- The idle layout: players standing still in a square, some pairs hidden and every fourth viewer at NEAR
local IDLE_SEED: number = 101
local IDLE_VIEWERS: number = 40
local IDLE_SPREAD: number = 600
local IDLE_RUNS: number = 30 -- Past a second, so the still repeat comes round
local IDLE_HIDDEN: number = 0.1 -- The share of pairs anti-ESP hides
local IDLE_NEAR_EVERY: number = 4

-- The fight: every pair relevant, every body moving and turning, hides reshuffled every few runs
local FIGHT_SEED: number = 202
local FIGHT_VIEWERS: number = 40
local FIGHT_CENTER: vector = vector.create(-192, 0, -192) -- Where cells of relevancy.leave from the play bound meet
local FIGHT_SPREAD: number = 100
local FIGHT_RUNS: number = 40
local FIGHT_STEP: number = 0.8 -- Studs a body may move along each axis a run, 16 a second
local FIGHT_TURN: number = 0.3 -- Radians a body may turn either way a run
local FIGHT_HIDDEN: number = 0.2
local FIGHT_SHUFFLE: number = 5 -- Runs between reshuffles of the hidden pairs
local FIGHT_JUMP: number = 0.05 -- A body's chance of a jump a run

-- The wide field: players crossing a map of sleepers, NPCs and bodies, pairs coming into range and leaving it
local FIELD_SEED: number = 303
local FIELD_VIEWERS: number = 40
local FIELD_SPREAD: number = 3000 -- The square the players start in
local FIELD_STEP: number = 20 -- Studs a player crosses a run, 400 a second
local FIELD_SLEEPERS: number = 400
local FIELD_SLEEPER_SPREAD: number = 6000
local FIELD_OTHERS: number = 10 -- NPCs, and as many bodies
local FIELD_OTHER_SPREAD: number = 4000
local FIELD_RUNS: number = 60
local FIELD_SWAP_RUN: number = 30 -- The run some sleepers go and as many come
local FIELD_SWAPPED: number = 20
local FIELD_RIM_FAR_RUN: number = 20 -- The run the rim viewer's distance goes to FULL, and back to NEAR
local FIELD_RIM_NEAR_RUN: number = 40
local FIELD_JUMP_RUN: number = 45 -- The run some players jump out of every pair's range at once
local FIELD_JUMPERS: number = 4
local FIELD_JUMP: number = 5000 -- Studs along x, away from the field's middle and inside the play bound

-- Bodies on the field's edges: the play bound's corner, the rim of a NEAR viewer and the rim of relevancy.leave
local BOUND: number = 8192 -- Constants.PLAY_BOUND
local CORNER: vector = vector.create(8000, 0, 8000)
local RIM: vector = vector.create(-4000, 0, 0)
local EDGE: vector = vector.create(0, 0, -6000)
local EDGE_START: number = 1100 -- Studs out the edge player starts, then walks in past the enter radius and back
local EDGE_IN: number = 940
local EDGE_WALK: number = 5

-- The tapped fight: sinks on some viewers and a moderator watching the first, so its copies and withheld block go
local TAPS_SEED: number = 404
local TAPS_VIEWERS: number = 30
local TAPS_CENTER: vector = vector.create(808, 0, 808)
local TAPS_SPREAD: number = 80
local TAPS_RUNS: number = 30
local TAPS_SINKS: number = 3 -- The first this many viewers, and the moderator, are observed
local TAPS_TARGET_HIDDEN: number = 0.3 -- The share of the target's pairs hidden, which its watcher is sent withheld
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)
local WATCH_FROM: number = 5
local WATCH_UNTIL: number = 25

-- The digests each layout gives, which change only with what a viewer is sent. They rest on the order Luau walks
-- the states table in, which the relay's own order follows
local EXPECTED: { [string]: string } = {
	idle = "9400a6ccbeffa3ce7176de662afd16a5d8e8e7b05a1186ac2e5530fb98874f3b",
	fight = "d191a0363bab1c2b04522e0fe169c6d0a62502a97a6ec3278ef2773403ba63c2",
	field = "8cffc2017ebdd59e3a9733c4e4837390e9949c9dfd6daac80222396ab8458f23",
	taps = "b0e1d6d53c986c91861d424a959c8c44c6089f003a9fe91843dd7dc6d6a77cd4",
}

type Generator = () -> number

-- What one layout's runs gave: its digest and the totals that show it reached what it is for
type Result = {
	digest: string,
	reveals: number,
	hides: number,
	changes: number,
	footsteps: number,
	withheld: number,
	frames: number,
	jumped: number, -- The pairs drawn as the jump put them out of range
	stale: number, -- And those still drawn out of range once its run was read
}

-- What one layout keeps while it runs
type Layout = {
	Harness: any,
	harness: any,
	clients: { any },
	names: { [any]: string },
	parts: { string },
	result: Result,
}

-- A seeded generator of numbers between 0 and 1
local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

-- A place in a square of a side around a center, on the ground
local function within(random: Generator, center: vector, side: number): vector
	return center + vector.create((random() - 0.5) * side, 0, (random() - 0.5) * side)
end

-- The look of a facing, a unit vector on the ground
local function lookOf(facing: number): vector
	return vector.create(-math.sin(facing), 0, -math.cos(facing))
end

-- The names of a send's recipients, in the order the relay listed them
local function label(layout: Layout, keys: { any }): string
	local names: { string } = {}
	for index: number, key: any in keys do
		names[index] = layout.names[key]
	end

	return table.concat(names, ",")
end

-- One part of the digest, its bytes behind their length so no two parts run together
local function add(layout: Layout, kind: string, name: string, data: buffer)
	table.insert(layout.parts, `{kind} {name} {buffer.len(data)} {buffer.tostring(data)}`)
end

--[[
    A layout's harness, with every block and withheld block it sends kept
    in order with its recipients' names
--]]

local function begin(): Layout
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	local layout: Layout = {
		Harness = Harness,
		harness = harness,
		clients = {},
		names = {},
		parts = {},
		result = {
			digest = "",
			reveals = 0,
			hides = 0,
			changes = 0,
			footsteps = 0,
			withheld = 0,
			frames = 0,
			jumped = 0,
			stale = 0,
		},
	}

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		add(layout, "block", label(layout, keys), data)
		Harness._deliver(self, keys, data)
	end

	harness._withhold = function (self: any, keys: { any }, data: buffer)
		add(layout, "withheld", label(layout, keys), data)
		Harness._withhold(self, keys, data)
	end

	return layout
end

-- A viewer, named for the digest, with a player body of its own at a place when owned
local function join(layout: Layout, name: string, at: vector, owned: boolean): any
	local client: any = layout.harness:viewer(name)
	layout.names[client.viewer.key] = name
	table.insert(layout.clients, client)

	client.viewer.position = at
	if owned then
		client.viewer.slot = layout.harness:spawn("Player", at)
	end

	return client
end

-- Hides a share of the other viewers' bodies from each viewer, and shows the rest
local function shuffle(layout: Layout, random: Generator, share: number)
	for _, client: any in layout.clients do
		for _, other: any in layout.clients do
			local slot: number? = other.viewer.slot
			if other ~= client and slot ~= nil then
				layout.harness:hide(client, slot, random() < share)
			end
		end
	end
end

-- Keeps each owned viewer where its body stands, looking where it faces
local function follow(layout: Layout)
	for _, client: any in layout.clients do
		local slot: number? = client.viewer.slot
		if slot ~= nil then
			local state: any = layout.harness.states[slot]
			client.viewer.position = state.position
			client.viewer.look = lookOf(state.facing)
		end
	end
end

-- One relay run, its reads added to the totals and, every KEYFRAMES runs, each viewer's keyframe to the digest
local function step(layout: Layout, run: number)
	layout.harness:run()

	local result: Result = layout.result
	for _, client: any in layout.clients do
		local seen: any = client.seen
		result.reveals += #seen.reveals
		result.hides += #seen.hides
		result.changes += #seen.changes
		result.footsteps += #seen.footsteps
		result.withheld += #seen.withheld
	end

	if run % KEYFRAMES == 0 then
		for _, client: any in layout.clients do
			add(layout, "keyframe", layout.names[client.viewer.key], layout.Harness.Relay.keyframe(client.viewer.key))
		end
	end
end

-- The layout's digest, with the relay's running counts last
local function finish(layout: Layout): Result
	local sent: number, cut: number = layout.Harness.Relay.counts()
	table.insert(layout.parts, `counts {sent} {cut}`)
	layout.result.digest = serde.hash("sha256", table.concat(layout.parts, "\n"))

	return layout.result
end

-- The pairs a layout's clients draw whose body is past relevancy.leave from them or gone from the states
local function farDrawn(layout: Layout): number
	local count: number = 0

	for _, client: any in layout.clients do
		for slot: number in client.drawn do
			local state: any = layout.harness.states[slot]
			if state == nil or vector.magnitude(state.position - client.viewer.position) > FULL then
				count += 1
			end
		end
	end

	return count
end

-- Moves every owned body by a step up to a length along each axis, turns it, and now and then jumps it
local function scuffle(layout: Layout, random: Generator, length: number, jump: number)
	for _, client: any in layout.clients do
		local slot: number? = client.viewer.slot
		if slot ~= nil then
			local state: any = layout.harness.states[slot]
			state.position += vector.create((random() - 0.5) * 2 * length, 0, (random() - 0.5) * 2 * length)
			state.facing += (random() - 0.5) * 2 * FIGHT_TURN

			if random() < jump then
				state.jumps = (state.jumps + 1) % 4
			end
		end
	end
end

local function idle(): Result
	local layout: Layout = begin()
	local random: Generator = generator(IDLE_SEED)

	for index: number = 1, IDLE_VIEWERS do
		local client: any = join(layout, `Idle{index}`, within(random, vector.zero, IDLE_SPREAD), true)
		layout.harness.states[client.viewer.slot].facing = random() * 2 * math.pi

		if index % IDLE_NEAR_EVERY == 0 then
			layout.Harness.Relay.setDistance(client.viewer.key, NEAR)
		end
	end

	shuffle(layout, random, IDLE_HIDDEN)
	follow(layout)

	for run: number = 1, IDLE_RUNS do
		step(layout, run)
	end

	return finish(layout)
end

local function fight(): Result
	local layout: Layout = begin()
	local random: Generator = generator(FIGHT_SEED)

	for index: number = 1, FIGHT_VIEWERS do
		join(layout, `Fight{index}`, within(random, FIGHT_CENTER, FIGHT_SPREAD), true)
	end

	for run: number = 1, FIGHT_RUNS do
		if run % FIGHT_SHUFFLE == 1 then
			shuffle(layout, random, FIGHT_HIDDEN)
		end

		scuffle(layout, random, FIGHT_STEP, FIGHT_JUMP)
		follow(layout)
		step(layout, run)
	end

	return finish(layout)
end

local function field(): Result
	local layout: Layout = begin()
	local harness: any = layout.harness
	local random: Generator = generator(FIELD_SEED)

	local headings: { vector } = {}
	for index: number = 1, FIELD_VIEWERS do
		local client: any = join(layout, `Field{index}`, within(random, vector.zero, FIELD_SPREAD), true)
		local facing: number = random() * 2 * math.pi
		harness.states[client.viewer.slot].facing = facing
		headings[index] = lookOf(facing) * FIELD_STEP
	end

	local sleepers: { number } = {}
	for _ = 1, FIELD_SLEEPERS do
		table.insert(sleepers, harness:spawn("Sleeper", within(random, vector.zero, FIELD_SLEEPER_SPREAD)))
	end

	for _ = 1, FIELD_OTHERS do
		harness:spawn("Npc", within(random, vector.zero, FIELD_OTHER_SPREAD))
		harness:spawn("Body", within(random, vector.zero, FIELD_OTHER_SPREAD))
	end

	-- The corner of the play bound, where the outermost bodies stand on it
	join(layout, "Corner", CORNER, false)
	harness:spawn("Sleeper", vector.create(BOUND, 0, BOUND))
	harness:spawn("Sleeper", vector.create(BOUND, 0, CORNER.z - NEAR * 2))
	harness:spawn("Sleeper", vector.create(CORNER.x - NEAR * 2, 0, BOUND))
	harness:spawn("Player", vector.create(BOUND, 0, CORNER.z))

	-- A NEAR viewer with a sleeper and an NPC exactly on its rim
	local rim: any = join(layout, "Rim", RIM, false)
	layout.Harness.Relay.setDistance(rim.viewer.key, NEAR)
	harness:spawn("Sleeper", RIM + vector.create(NEAR, 0, 0))
	harness:spawn("Npc", RIM + vector.create(0, 0, NEAR))

	-- A viewer a player walks in on past the enter radius, then back out to stand exactly at relevancy.leave
	join(layout, "Edge", EDGE, false)
	local edge: number = harness:spawn("Player", EDGE + vector.create(0, 0, EDGE_START))

	for run: number = 1, FIELD_RUNS do
		for index: number, client: any in layout.clients do
			local slot: number? = client.viewer.slot
			if slot ~= nil and index <= FIELD_VIEWERS then
				harness.states[slot].position += headings[index]
			end
		end

		local walked: number = harness.states[edge].position.z - EDGE.z
		if run <= (EDGE_START - EDGE_IN) / EDGE_WALK then
			harness.states[edge].position -= vector.create(0, 0, EDGE_WALK)
		elseif walked < FULL then
			harness.states[edge].position += vector.create(0, 0, math.min(EDGE_WALK, FULL - walked))
		end

		if run == FIELD_RIM_FAR_RUN then
			layout.Harness.Relay.setDistance(rim.viewer.key, FULL)
		elseif run == FIELD_RIM_NEAR_RUN then
			layout.Harness.Relay.setDistance(rim.viewer.key, NEAR)
		end

		-- Some sleepers go, some of them tracked, and as many come elsewhere, so the states' walk changes
		if run == FIELD_SWAP_RUN then
			for index: number = 1, FIELD_SWAPPED do
				harness:despawn(sleepers[index * 7])
				harness:spawn("Sleeper", within(random, vector.zero, FIELD_SLEEPER_SPREAD))
			end
		end

		-- Some players jump far out in one run, so every pair of theirs leaves range at once, many of them for cells
		-- past those the viewer's distance spans
		if run == FIELD_JUMP_RUN then
			for index: number = 1, FIELD_JUMPERS do
				local state: any = harness.states[layout.clients[index].viewer.slot]
				local away: number = state.position.x < 0 and -FIELD_JUMP or FIELD_JUMP
				state.position += vector.create(away, 0, 0)
			end
		end

		follow(layout)
		if run == FIELD_JUMP_RUN then
			layout.result.jumped = farDrawn(layout)
		end

		step(layout, run)
		if run == FIELD_JUMP_RUN then
			layout.result.stale = farDrawn(layout)
		end
	end

	return finish(layout)
end

local function taps(): Result
	local layout: Layout = begin()
	local harness: any = layout.harness
	local random: Generator = generator(TAPS_SEED)

	for index: number = 1, TAPS_VIEWERS do
		join(layout, `Tapped{index}`, within(random, TAPS_CENTER, TAPS_SPREAD), true)
	end

	local target: any = layout.clients[1]
	local moderator: any = join(layout, "Moderator", MODERATOR_AT, false)

	shuffle(layout, random, FIGHT_HIDDEN)
	for _, other: any in layout.clients do
		local slot: number? = other.viewer.slot
		if other ~= target and slot ~= nil and random() < TAPS_TARGET_HIDDEN then
			harness:hide(target, slot, true)
		end
	end

	-- Each sink's frames kept by its viewer, since the taps hand frames out in no fixed order
	local observed: { any } = { moderator }
	for index: number = 1, TAPS_SINKS do
		table.insert(observed, layout.clients[index])
	end

	local frames: { [string]: { buffer } } = {}
	local stops: { () -> () } = {}
	for _, client: any in observed do
		local name: string = layout.names[client.viewer.key]
		frames[name] = {}
		table.insert(
			stops,
			layout.Harness.Taps.observe(client.viewer.key, function (_: number, data: buffer)
				table.insert(frames[name], data)
			end)
		)
	end

	for run: number = 1, TAPS_RUNS do
		if run == WATCH_FROM then
			harness:watch(moderator, target)
		elseif run == WATCH_UNTIL then
			harness:watch(moderator, nil)
		end

		scuffle(layout, random, FIGHT_STEP, FIGHT_JUMP)
		follow(layout)
		step(layout, run)

		for _, client: any in observed do
			local name: string = layout.names[client.viewer.key]
			for _, frame: buffer in frames[name] do
				add(layout, "frame", name, frame)
				layout.result.frames += 1
			end

			table.clear(frames[name])
		end
	end

	for _, stop: () -> () in stops do
		stop()
	end

	return finish(layout)
end

return function (): (boolean, string | nil)
	local idled: Result = idle()
	local fought: Result = fight()
	local fielded: Result = field()
	local tapped: Result = taps()

	-- Each layout reaches what it is there for, so its digest pins it
	if idled.reveals == 0 or idled.changes == 0 then
		return false, "The idle layout revealed nothing or sent no still repeat"
	elseif fought.hides == 0 or fought.changes == 0 or fought.footsteps == 0 then
		return false, "The fight hid no one, sent no change or heard no step"
	elseif fielded.reveals == 0 or fielded.hides == 0 then
		return false, "The field's bodies never came into range or never left it"
	elseif fielded.jumped == 0 then
		return false, "The field's jump put no pair a client draws out of range"
	elseif fielded.stale ~= 0 then
		return false,
			`{fielded.stale} of the {fielded.jumped} pairs the jump put out of range were still drawn after its run`
	elseif tapped.withheld == 0 or tapped.frames == 0 then
		return false, "The tapped fight sent its moderator no withheld block or its sinks no frame"
	end

	for name: string, result: Result in { idle = idled, fight = fought, field = fielded, taps = tapped } do
		if result.digest ~= EXPECTED[name] then
			return false,
				`The {name} layout's blocks, frames and keyframes digest to {result.digest}, not {EXPECTED[name]}`
		end
	end

	return true, nil
end
