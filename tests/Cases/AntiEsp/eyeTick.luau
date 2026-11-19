--[[
    Seeded fights stepping on ticks, three slices a tick, give the verdicts,
    rays and counts pinned, and clear each viewer's eye at most once a tick
    and once more after each move of its own slot between ticks
--]]

--!strict
local serde = require("@lune/serde")

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807
local WRAP: number = 2 ^ 16 -- The ticks world.tick wraps in
local HEARTBEAT: number = 1 / 60 -- Seconds between slices
local SLICES: number = 3 -- A tick's Heartbeats at the example's 20 Hz
local TICK_RATE: number = 20
local SHARE: number = 1 -- Seconds of lying tests first, the harness's whole slice, so no test's order rests on the clock

-- Low walls across x: a plane every SPACING studs, its top TOP studs up and TOP_STEP more for each of the next two
local SPACING: number = 16
local TOP: number = 3.6
local TOP_STEP: number = 0.5

-- A body's tick: a step up to STEP studs along each axis, a turn up to TURN radians either way, and now and then a
-- new lean or posture
local STEP: number = 0.8
local TURN: number = 0.3
local LEAN_CHANCE: number = 0.3
local POSTURE_CHANCE: number = 0.1

local TEAMS: number = 4 -- Of each four players, one carries team 1, one team 2 and two none
local REBORN_EVERY: number = 10 -- Ticks between new lives, on a tick, each a player's
local REBORN_AT: number = 5
local TELEPORT_EVERY: number = 7 -- Ticks between a viewer's landing before its tick's second slice
local TELEPORT_AT: number = 3
local SLEEPER_EVERY: number = 5 -- Ticks between a sleeper's move before its tick's third slice
local SLEEPER_AT: number = 2

type Generator = () -> number

type Layout = {
	seed: number,
	players: number,
	sleepers: number,
	center: vector,
	spread: number,
	ticks: number,
}

local LAYOUTS: { [string]: Layout } = {
	small = { seed = 11, players = 16, sleepers = 4, center = vector.create(300, 0, -200), spread = 90, ticks = 30 },
	wide = { seed = 23, players = 24, sleepers = 6, center = vector.create(-1500, 0, 2500), spread = 140, ticks = 30 },
}

-- Each layout's digest, which the unchanged module gave with every eye cleared afresh each slice
local EXPECTED: { [string]: string } = {
	small = "40fc6295f8a29ee63c1f04bbde21a39a60e5a7520b77e677a659c36d85092135",
	wide = "a7bc79c466e29fd79577bd9ace5e124ab84945d8af3e655871831dd53a3c4c93",
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

-- Whether a ray crosses a wall's plane below its top
local function wall(origin: vector, direction: vector): boolean
	local finish: vector = origin + direction
	local low: number = math.min(origin.x, finish.x)
	local high: number = math.max(origin.x, finish.x)

	for plane: number = math.ceil(low / SPACING), math.floor(high / SPACING) do
		local share: number = (plane * SPACING - origin.x) / direction.x
		if origin.y + direction.y * share < TOP + plane % 3 * TOP_STEP then
			return true
		end
	end

	return false
end

local Scratch: buffer = buffer.create(48)

-- A ray's origin and end by their 8 bytes each
local function rayText(origin: vector, finish: vector): string
	buffer.writef64(Scratch, 0, origin.x)
	buffer.writef64(Scratch, 8, origin.y)
	buffer.writef64(Scratch, 16, origin.z)
	buffer.writef64(Scratch, 24, finish.x)
	buffer.writef64(Scratch, 32, finish.y)
	buffer.writef64(Scratch, 40, finish.z)

	return buffer.tostring(Scratch)
end

--[[
    One layout's ticks: the players step, then three slices run, the
    relay's asks after the first, with landings and sleeper moves between
    ticks. Gives the digest of every slice's counts and rays and every
    ask's answer and reason, the eye clears, and the first tick a body's
    eye was cleared past the bound
--]]

local function run(layout: Layout): (string, number, string?)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = SHARE
	end)
	local AntiEsp: any = Harness.AntiEsp
	local Eye: any = Harness.Eye
	local world: any = harness.world
	local step: any = harness.shared.step
	local random: Generator = generator(layout.seed)
	local parts: { string } = {}
	harness.wall = wall

	local eyes: { [string]: number } = { Stand = step.eyeStanding, Crouch = step.eyeCrouched, Downed = step.eyeDowned }
	local postures: { string } = { "Stand", "Crouch", "Downed" }

	local players: { number } = {}
	local viewers: { any } = {}
	for index: number = 1, layout.players do
		local slot: number, viewer: any = harness:player(`P{index}`, within(random, layout.center, layout.spread))
		players[index] = slot
		viewers[index] = viewer

		local team: number = index % TEAMS
		if team < 2 then
			AntiEsp.setTeam(slot, team + 1)
		end
	end

	local targets: { number } = table.clone(players)
	local sleepers: { number } = {}
	for index: number = 1, layout.sleepers do
		sleepers[index] = harness:body("Sleeper", within(random, layout.center, layout.spread), random() * 2 * math.pi)
		table.insert(targets, sleepers[index])
	end

	-- Each body's eye clears this tick, and the moves of its own slot that allow one more each
	local clear: any = Eye.clear
	local calls: { [any]: number } = {}
	local allowed: { [any]: number } = {}
	local total: number = 0
	local over: string? = nil
	local current: number = 0

	Eye.clear = function (state: any, inWorld: any): vector
		local count: number = (calls[state] or 0) + 1
		calls[state] = count
		total += 1

		if count > 1 + (allowed[state] or 0) and over == nil then
			over = `A body's eye was cleared {count} times in tick {current}`
		end

		return clear(state, inWorld)
	end

	local now: number = 0
	local round: number = 0
	local slices: number = 0

	for tick: number = 1, layout.ticks do
		current = tick
		world.clock = tick
		world.tick = tick % WRAP
		table.clear(calls)
		table.clear(allowed)

		for _, slot: number in players do
			local state: any = harness.states[slot]
			local move: vector = vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
			state.position += move
			state.velocity = move * TICK_RATE
			state.facing += (random() - 0.5) * 2 * TURN

			if random() < LEAN_CHANCE then
				state.lean = (random() * 2 - 1) * step.lean
			end

			if random() < POSTURE_CHANCE then
				local posture: string = postures[math.floor(random() * #postures) + 1]
				state.posture = posture
				state.eyeHeight = eyes[posture]
			end
		end

		if tick % REBORN_EVERY == REBORN_AT then
			harness:reborn(players[1 + tick % #players])
		end

		for index: number, viewer: any in viewers do
			viewer.position = harness.states[players[index]].position
		end

		for slice: number = 1, SLICES do
			-- A viewer's landing between ticks, which moves its own slot
			if slice == 2 and tick % TELEPORT_EVERY == TELEPORT_AT then
				local index: number = 1 + tick % #players
				local slot: number = players[index]
				harness:move(slot, within(random, layout.center, layout.spread), viewers[index])
				AntiEsp.moved(slot)

				local state: any = harness.states[slot]
				allowed[state] = (allowed[state] or 0) + 1
				table.insert(parts, `teleport {tick} {slot}`)
			end

			if slice == 3 and tick % SLEEPER_EVERY == SLEEPER_AT then
				local slot: number = sleepers[1 + tick % #sleepers]
				harness.states[slot].position = within(random, layout.center, layout.spread)
				AntiEsp.moved(slot)
				table.insert(parts, `sleeper {tick} {slot}`)
			end

			harness:slice(now)
			now += HEARTBEAT
			slices += 1

			local tests: number, hiddenTests: number, failOpens: number = AntiEsp.counts()
			local lyingTests: number, lyingWaiting: number = AntiEsp.lying()
			table.insert(
				parts,
				`slice {slices} {tests} {hiddenTests} {failOpens} {lyingTests} {lyingWaiting} {#harness.rays}`
			)

			for _, ray: any in harness.rays do
				table.insert(parts, rayText(ray.origin, ray.to))
			end

			-- The relay's run, after the tick's first slice as the server's stages run
			if slice == 1 then
				round += 1

				for index: number, viewer: any in viewers do
					for _, target: number in targets do
						if target ~= players[index] then
							local hidden: boolean = AntiEsp.isHidden(viewer, target)
							local reason: string = AntiEsp.reason(viewer.key, target)
							table.insert(parts, `ask {round} {index} {target} {hidden} {reason}`)
						end
					end
				end
			end
		end
	end

	return serde.hash("sha256", table.concat(parts, "\n")), total, over
end

return function (): (boolean, string | nil)
	for _, name: string in { "small", "wide" } do
		local layout: Layout = LAYOUTS[name]
		local digest: string, total: number, over: string? = run(layout)

		if digest ~= EXPECTED[name] then
			return false, `The {name} layout's verdicts, rays and counts digest to {digest}, not {EXPECTED[name]}`
		elseif over then
			return false, `In the {name} layout: {over}`
		elseif total == 0 or total > layout.players * layout.ticks + layout.ticks // TELEPORT_EVERY + 1 then
			return false, `The {name} layout cleared {total} eyes over {layout.ticks} ticks of {layout.players} viewers`
		end
	end

	return true, nil
end
