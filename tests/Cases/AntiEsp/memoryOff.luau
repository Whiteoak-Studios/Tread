--[[
    With verdict memory off, never on or flipped on and off, a seeded scene
    gives every reason, count and ray, bit for bit, as anti-ESP with no
    verdict memory does, pinned by their digest, and no ray asks what it met
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXPECTED: string = "e6b25d00" -- The scene's reasons, counts and ray bits, as anti-ESP with no verdict memory gives them
local SLICE: number = 60 -- Seconds a full slice and its lying share may take, so no test order rests on the clock
local SEED: number = 20261120
local MULTIPLIER: number = 16807
local MODULUS: number = 2147483647
local STEPS: number = 150
local EVENTS: number = 9 -- A step's change is one of the first 7 of these, or none
local STRAY: number = 9
local SPEED: number = 20
local OFFSETS: number = 5
local DELAYS: { number } = { 1 / 60, 1 / 30, 0.1, 0.2 }
local SLICINGS: number = 6
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local FNV_OFFSET: number = 2166136261
local FNV_PRIME: number = 16777619
local RAY_FORMAT: string = "<ffffff"
local COUNT_FORMAT: string = "<I4I4I4I4I4"
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false
local NEVER_ON: boolean = false -- A scene whose memory is never turned on
local FLIPPED: boolean = true -- And one whose memory is turned on and off before it starts

local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "North", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "East", kind = "Player", at = vector.create(40, 0, 10), sees = true },
	{ name = "Runner", kind = "Player", at = vector.create(0, 0, -40), sees = false },
	{ name = "Lurker", kind = "Player", at = vector.create(20, 0, -35), sees = false },
	{ name = "Crawler", kind = "Player", at = vector.create(-25, 0, -50), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-10, 0, -60), sees = false },
}

-- FNV-1a over a string's bytes, folded into a running hash
local function fold(hash: number, text: string): number
	for index: number = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * FNV_PRIME) % 2 ^ 32
	end

	return hash
end

-- The scene's digest, and how many of its rays asked the occluder what they met
local function scene(toggle: boolean): (string, number)
	local seed: number = SEED
	local function roll(count: number): number
		seed = seed * MULTIPLIER % MODULUS

		return seed % count
	end

	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = SLICE
	end)
	local AntiEsp: any = Harness.AntiEsp

	-- Turned on and off again before anything is asked, as a dev bench's flip leaves it
	if toggle then
		AntiEsp.useMemory(ON)
		AntiEsp.useMemory(OFF)
	end

	local offset: number = 0
	harness.wall = function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		return (math.floor(finish.x) + math.floor(finish.y * 4) + math.floor(finish.z) + offset) % OFFSETS ~= 0
	end

	local slots: { [string]: number } = {}
	local viewers: { any } = {}
	local asked: { number } = {}
	local movers: { string } = {}

	for _, body in BODIES do
		local slot: number = harness:body(body.kind, body.at)
		slots[body.name] = slot
		table.insert(asked, slot)
		table.insert(movers, body.name)

		if body.sees then
			table.insert(viewers, harness:viewer(body.name, slot))
		end
	end

	table.insert(viewers, harness:viewer("Ghost", nil))

	local function viewerOf(slot: number): any
		for _, viewer: any in viewers do
			if viewer.slot == slot then
				return viewer
			end
		end

		return nil
	end

	local hash: number = FNV_OFFSET
	local now: number = 0

	for _ = 1, STEPS do
		local event: number = roll(EVENTS)
		local name: string = movers[roll(#movers) + 1]
		local slot: number = slots[name]
		local state: any = harness.states[slot]

		if event == 0 then
			local step: vector = vector.create(roll(STRAY) - STRAY // 2, 0, roll(STRAY) - STRAY // 2)
			harness:move(slot, state.position + step, viewerOf(slot))
			state.velocity = step * SPEED
		elseif event == 1 then
			state.velocity = vector.zero
		elseif event == 2 then
			state.posture = POSTURES[roll(#POSTURES) + 1]
		elseif event == 3 then
			harness:move(slot, vector.create(roll(80) - 40, 0, roll(80) - 60), viewerOf(slot))
			AntiEsp.moved(slot)
		elseif event == 4 and select(2, Harness.Slots.get(slot)).kind ~= "Sleeper" then
			harness:reborn(slot)
		elseif event == 5 then
			local _, entry: any = Harness.Slots.get(slots.Crawler)
			local kind: string = entry.kind == "Sleeper" and "Player" or "Sleeper"
			Harness.Slots.setEntry(slots.Crawler, { kind = kind, rig = "A" })
		elseif event == 6 then
			AntiEsp.leave(viewers[roll(#viewers) + 1].key)
		end

		harness.world.clock += 1
		offset = roll(OFFSETS)

		for _, viewer: any in viewers do
			for _, target: number in asked do
				if target ~= viewer.slot then
					AntiEsp.isHidden(viewer, target)
				end
			end
		end

		local slicing: number = roll(SLICINGS)
		if slicing ~= 0 then
			now += DELAYS[roll(#DELAYS) + 1]
			local budget: number = SLICE
			if slicing == 1 then
				budget = 0
			end

			harness:slice(now, budget)
		end

		local parts: { string } = {}
		for _, viewer: any in viewers do
			for _, target: number in asked do
				table.insert(parts, AntiEsp.reason(viewer.key, target))
			end
		end

		local tests: number, hidden: number, failOpens: number = AntiEsp.counts()
		local lying: number, waiting: number = AntiEsp.lying()
		table.insert(parts, string.pack(COUNT_FORMAT, tests, hidden, failOpens, lying, waiting))

		for _, ray: any in harness.rays do
			table.insert(
				parts,
				string.pack(RAY_FORMAT, ray.origin.x, ray.origin.y, ray.origin.z, ray.to.x, ray.to.y, ray.to.z)
			)
		end

		table.clear(harness.rays)
		hash = fold(hash, table.concat(parts, "|"))
	end

	return string.format("%08x", hash), harness.occluded
end

return function (): (boolean, string | nil)
	local never: string, neverAsked: number = scene(NEVER_ON)
	if never ~= EXPECTED then
		return false, `With memory never on the scene's digest was {never}, not {EXPECTED}`
	elseif neverAsked ~= 0 then
		return false, `With memory never on the scene asked the occluder {neverAsked} times`
	end

	local flipped: string, flippedAsked: number = scene(FLIPPED)
	if flipped ~= EXPECTED then
		return false, `With memory turned on and off the scene's digest was {flipped}, not {EXPECTED}`
	elseif flippedAsked ~= 0 then
		return false, `With memory turned on and off the scene asked the occluder {flippedAsked} times`
	end

	return true, nil
end
