--[[
    A seeded crowd, some of it standing still, whose looks and held items
    change while sent, hidden and revealed, before and after far bodies
    spread it across cells, gives every block, keyframe and count the digest
--]]

--!strict
local serde = require("@lune/serde")

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807
local SEED: number = 505

-- The crowd: every pair relevant, around a corner where four of the grid's cells meet, with a few phone viewers
local VIEWERS: number = 60
local CENTER: vector = vector.create(-192, 0, -192)
local SPREAD: number = 120
local NEAR: number = 250 -- A phone's render distance, which every NEAR_EVERY-th viewer sets
local NEAR_EVERY: number = 6
local STILL_EVERY: number = 4 -- Every this many bodies stands still, so its rest and still repeats come round
local RUNS: number = 32 -- Past a second, so the still repeat comes round
local STEP: number = 0.8 -- Studs a body may move along each axis a run
local TURN: number = 0.3 -- Radians a body may turn either way a run
local HIDDEN: number = 0.2 -- The share of pairs anti-ESP hides, reshuffled every SHUFFLE runs
local SHUFFLE: number = 4
local RESTYLED: number = 0.1 -- Each body's chance of a new look a run, and of a new held item
local LOOKS: number = 4 -- The looks and held items a body picks from
local KEYFRAMES: number = 16 -- Every this many runs each viewer's keyframe joins the digest

-- The far group, players with no viewer, which come on FAR_RUN so no viewer's cells hold every body from then on
local FAR_RUN: number = 17
local FAR_BODIES: number = 8
local FAR_CENTER: vector = vector.create(3000, 0, 3000)
local FAR_SPREAD: number = 200

-- The digest the layout gives, which changes only with what a viewer is sent. It rests on the order Luau walks the
-- states table in, which the relay's own order follows
local EXPECTED: string = "6dbd5fc995cf5087548a8a932d090ef694f511949b947add530eb6aef00f5b75"

type Generator = () -> number

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

-- One of the looks or held items a body picks from, by its index from 1
local function pick(random: Generator, field: string): { [string]: any }
	return { [field] = math.floor(random() * LOOKS) + 1 }
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local random: Generator = generator(SEED)
	local clients: { any } = {}
	local names: { [any]: string } = {}
	local parts: { string } = {}
	local looks: number, helds: number, reveals: number, hides: number = 0, 0, 0, 0

	-- Each block and withheld block, its bytes behind their length and its recipients' names
	local function add(kind: string, name: string, data: buffer)
		table.insert(parts, `{kind} {name} {buffer.len(data)} {buffer.tostring(data)}`)
	end

	local function label(keys: { any }): string
		local list: { string } = {}
		for index: number, key: any in keys do
			list[index] = names[key]
		end

		return table.concat(list, ",")
	end

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		add("block", label(keys), data)
		Harness._deliver(self, keys, data)
	end

	harness._withhold = function (self: any, keys: { any }, data: buffer)
		add("withheld", label(keys), data)
		Harness._withhold(self, keys, data)
	end

	for index: number = 1, VIEWERS do
		local name: string = `Crowd{index}`
		local client: any = harness:viewer(name)
		local at: vector = within(random, CENTER, SPREAD)
		names[client.viewer.key] = name
		table.insert(clients, client)

		client.viewer.position = at
		client.viewer.slot = harness:spawn("Player", at)
		harness.states[client.viewer.slot].facing = random() * 2 * math.pi

		if index % NEAR_EVERY == 0 then
			Harness.Relay.setDistance(client.viewer.key, NEAR)
		end
	end

	for run: number = 1, RUNS do
		if run % SHUFFLE == 1 then
			for _, client: any in clients do
				for _, other: any in clients do
					if other ~= client then
						harness:hide(client, other.viewer.slot, random() < HIDDEN)
					end
				end
			end
		end

		if run == FAR_RUN then
			for _ = 1, FAR_BODIES do
				harness:spawn("Player", within(random, FAR_CENTER, FAR_SPREAD))
			end
		end

		-- The rest step and turn, and some of every body change their look or held item
		for index: number, client: any in clients do
			local slot: number = client.viewer.slot
			local state: any = harness.states[slot]
			if index % STILL_EVERY ~= 0 then
				state.position += vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
				state.facing += (random() - 0.5) * 2 * TURN
			end

			if random() < RESTYLED then
				Harness.Relay.setLook(slot, pick(random, "head"))
			end

			if random() < RESTYLED then
				state.held = pick(random, "item")
			end

			client.viewer.position = state.position
			client.viewer.look = lookOf(state.facing)
		end

		harness:run()

		for _, client: any in clients do
			local seen: any = client.seen
			reveals += #seen.reveals
			hides += #seen.hides

			for _, look: any in seen.looks do
				if look.look ~= nil then
					looks += 1
				end

				if look.held ~= nil then
					helds += 1
				end
			end
		end

		if run % KEYFRAMES == 0 then
			for _, client: any in clients do
				add("keyframe", names[client.viewer.key], Harness.Relay.keyframe(client.viewer.key))
			end
		end
	end

	local sent: number, cut: number = Harness.Relay.counts()
	table.insert(parts, `counts {sent} {cut}`)
	local digest: string = serde.hash("sha256", table.concat(parts, "\n"))

	-- The layout reaches what it is there for, so its digest pins it
	if looks == 0 or helds == 0 then
		return false, "The crowd's looks and held items changed, yet no look entry carried one"
	elseif reveals == 0 or hides == 0 then
		return false, "The crowd's reshuffled hides revealed or hid no one"
	elseif digest ~= EXPECTED then
		return false, `The crowd's blocks, keyframes and counts digest to {digest}, not {EXPECTED}`
	end

	return true, nil
end
