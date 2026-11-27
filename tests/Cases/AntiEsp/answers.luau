--[[
    Through seeded runs and slices, every relay ask gives what a stand-in
    reads from the answers taken at its run's start, which hold through the
    run, and a twin that never takes them answers, tests and counts the same
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local SEED: number = 20261116 -- Park and Miller's generator's start, any whole number from 1 below its modulus
local MULTIPLIER: number = 16807
local MODULUS: number = 2147483647
local STEPS: number = 240
local EVENTS: number = 14 -- A step's change to the world is one of the first six of these, or none
local LEFT_OUT: number = 8 -- One ask in this many is left out of its run
local STRAY: number = 21 -- Studs a step moves a body across each axis, centered on 0
local REACH: number = 500 -- Studs from the origin a body may stray to, inside the play bound
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row
local LYING_SHARE: number = 1 -- Seconds, the harness's whole slice, so each slice tests its sleepers first in one order
local RED: number = 1
local BLUE: number = 2
local DELAYS: { number } = { 0.05, 0.1, 0.2 } -- Seconds from one slice to the next, the last past the fail-open time
local REASONS: { string } = { "Clear", "Hold", "FailOpen", "Hidden", "Untested", "Teammate", "Npc" }

-- The answers' kinds
local FREE: number = 0
local PLAYER: number = 1
local NPC: number = 3

-- What the wall answers: no ray blocked, every ray blocked, or some by where they end
local OPEN: number = 0
local SOLID: number = 1
local PATTERNS: number = 4 -- The modes a step picks from, the last two both the pattern
local OFFSETS: number = 5

-- Each body by its name and kind, where it starts, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "First", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Second", kind = "Player", at = vector.create(40, 0, 0), sees = true },
	{ name = "Far", kind = "Player", at = vector.create(0, 0, 300), sees = true },
	{ name = "Near", kind = "Player", at = vector.create(0, 0, -30), sees = false },
	{ name = "Wanderer", kind = "Player", at = vector.create(-60, 0, -80), sees = false },
	{ name = "Distant", kind = "Player", at = vector.create(0, 0, -400), sees = false },
	{ name = "Guard", kind = "Npc", at = vector.create(20, 0, -20), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-20, 0, -40), sees = false },
	{ name = "Body", kind = "Body", at = vector.create(30, 0, -60), sees = false },
}

local GONE: string = "Distant" -- Released halfway, so its slot is free with its pairs still kept
local SLEEPS: { string } = { "Near", "Wanderer", "Sleeper" } -- The bodies a step may put to sleep or wake

-- One harness and the bodies and viewers it holds, built the same on both sides
type Side = {
	harness: any,
	AntiEsp: any,
	Slots: any,
	viewers: { any },
	viewerOf: { [number]: any }, -- Each body's viewer by its slot, for those that see
	slots: { [string]: number },
}

-- Every ray's origin and end the same and in the same order
local function sameRays(rays: { any }, others: { any }): boolean
	if #rays ~= #others then
		return false
	end

	for index: number, ray: any in rays do
		local other: any = others[index]
		if ray.origin ~= other.origin or ray.to ~= other.to then
			return false
		end
	end

	return true
end

--[[
    What a relay worker's stand-in answers from the answers, as isHidden's
    own order goes: a free slot or an NPC shown, a player carrying the team
    of the viewer's own slot shown, then the slot's bit in the viewer's row
--]]

local function shown(answers: any, row: number, rowBytes: number, own: number?, slot: number): boolean
	local kind: number = buffer.readu8(answers.kinds, slot)
	if kind == FREE or kind == NPC then
		return true
	elseif
		kind == PLAYER
		and own ~= nil
		and buffer.readf64(answers.teams, own * 8) == buffer.readf64(answers.teams, slot * 8)
	then
		return true
	end

	local byte: number = buffer.readu8(answers.visible, row * rowBytes + slot // BITS)

	return bit32.btest(byte, bit32.lshift(1, slot % BITS))
end

-- The answers' three buffers as one string, to tell whether two takes gave the same
local function bytesOf(answers: any): string
	return buffer.tostring(answers.kinds) .. buffer.tostring(answers.teams) .. buffer.tostring(answers.visible)
end

return function (): (boolean, string | nil)
	local Constants: any = Environment.load(CONSTANTS)
	local rowBytes: number = Constants.SLOTS // BITS
	local free: number = Constants.SLOTS - 1 -- A slot no body takes

	local seed: number = SEED
	local function roll(count: number): number
		seed = seed * MULTIPLIER % MODULUS

		return seed % count
	end

	local mode: number = OPEN
	local offset: number = 0
	local function wall(origin: vector, direction: vector): boolean
		if mode == OPEN then
			return false
		elseif mode == SOLID then
			return true
		end

		local finish: vector = origin + direction

		return (math.floor(finish.x) + math.floor(finish.y * 4) + math.floor(finish.z) + offset) % OFFSETS ~= 0
	end

	local function side(): Side
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(function (_: any, server: any)
			server.antiEsp.lyingShare = LYING_SHARE
		end)
		harness.wall = wall

		local built: Side = {
			harness = harness,
			AntiEsp = Harness.AntiEsp,
			Slots = Harness.Slots,
			viewers = {},
			viewerOf = {},
			slots = {},
		}

		for _, body in BODIES do
			local slot: number = harness:body(body.kind, body.at)
			built.slots[body.name] = slot

			if body.sees then
				local viewer: any = harness:viewer(body.name, slot)
				table.insert(built.viewers, viewer)
				built.viewerOf[slot] = viewer
			end
		end

		table.insert(built.viewers, harness:viewer("Eye", nil))

		return built
	end

	local taker: Side = side()
	local twin: Side = side()

	local function both(change: (side: Side) -> ())
		change(taker)
		change(twin)
	end

	-- Every body's slot, the same on both sides, then the free one, in the order each run asks
	local asked: { number } = {}
	local movable: { number } = {}
	for _, body in BODIES do
		table.insert(asked, taker.slots[body.name])
		table.insert(movable, taker.slots[body.name])
	end
	table.insert(asked, free)

	local seen: { [string]: number } = {}
	local frees: number = 0
	local lefts: number = 0
	local reborns: number = 0
	local sleeps: number = 0
	local wakes: number = 0
	local now: number = 0

	both(function (built: Side)
		built.AntiEsp.setTeam(built.slots.First, RED)
		built.AntiEsp.setTeam(built.slots.Near, RED)
		built.AntiEsp.setTeam(built.slots.Sleeper, RED)
		built.AntiEsp.setTeam(built.slots.Second, BLUE)
		built.AntiEsp.setTeam(built.slots.Wanderer, BLUE)
	end)

	for step: number = 1, STEPS do
		-- The world changes between runs, the same on both sides
		if step == STEPS // 2 then
			local gone: number = taker.slots[GONE]
			table.remove(movable, table.find(movable, gone))

			both(function (built: Side)
				built.Slots.release(gone)
				built.harness.states[gone] = nil
			end)
		end

		local event: number = roll(EVENTS)
		local slot: number = movable[roll(#movable) + 1]
		local _, entry: any = taker.Slots.get(slot)

		-- The harness's new life takes every other free slot in turn, which a sleeper can't past the reserve
		if event == 0 and entry.kind ~= "Sleeper" then
			reborns += 1
			both(function (built: Side)
				built.harness:reborn(slot)
			end)
		elseif event == 1 then
			local sleeper: number = taker.slots[SLEEPS[roll(#SLEEPS) + 1]]
			local _, lying: any = taker.Slots.get(sleeper)
			local kind: string = "Sleeper"

			if lying.kind == "Sleeper" then
				kind = "Player"
				wakes += 1
			else
				sleeps += 1
			end

			both(function (built: Side)
				built.Slots.setEntry(sleeper, { kind = kind, rig = "A" })
			end)
		elseif event == 2 then
			local team: number? = nil
			if roll(3) ~= 0 then
				team = roll(2) == 0 and RED or BLUE
			end

			both(function (built: Side)
				built.AntiEsp.setTeam(slot, team)
			end)
		elseif event == 3 then
			both(function (built: Side)
				built.AntiEsp.moved(slot)
			end)
		elseif event == 4 then
			local leaving: number = roll(#taker.viewers) + 1

			both(function (built: Side)
				built.AntiEsp.leave(built.viewers[leaving].key)
			end)
		end

		local stray: vector = vector.create(roll(STRAY) - STRAY // 2, 0, roll(STRAY) - STRAY // 2)
		local position: vector = taker.harness.states[slot].position + stray
		position = vector.create(math.clamp(position.x, -REACH, REACH), 0, math.clamp(position.z, -REACH, REACH))

		both(function (built: Side)
			built.harness:move(slot, position, built.viewerOf[slot])
		end)

		mode = roll(PATTERNS)
		offset = roll(OFFSETS)

		-- No slice, so two runs share a round; a starved slice that tests nothing; or one with time for every test
		local slicing: number = roll(5)
		if slicing ~= 0 then
			now += DELAYS[roll(#DELAYS) + 1]
			local budget: number? = nil
			if slicing == 1 then
				budget = 0
			end

			both(function (built: Side)
				built.harness:slice(now, budget)
			end)

			if not sameRays(taker.harness.rays, twin.harness.rays) then
				return false, `Step {step}'s slice cast other rays on the side that took the answers`
			end
		end

		-- The run: the answers taken at its start, then each viewer's asks in the walk's order
		local answers: any = taker.AntiEsp.answers(taker.viewers)
		if buffer.len(answers.kinds) ~= Constants.SLOTS or buffer.len(answers.teams) ~= Constants.SLOTS * 8 then
			return false,
				`Step {step}'s answers held {buffer.len(answers.kinds)} kinds and {buffer.len(answers.teams)} B of teams`
		elseif buffer.len(answers.visible) ~= #taker.viewers * rowBytes then
			return false,
				`Step {step}'s answers held {buffer.len(answers.visible)} B of rows for {#taker.viewers} viewers`
		end

		local before: string = bytesOf(answers)

		for index: number, viewer: any in taker.viewers do
			local other: any = twin.viewers[index]

			for _, target: number in asked do
				if target == viewer.slot then
					continue
				elseif roll(LEFT_OUT) == 0 then
					lefts += 1
					continue
				end

				local visible: boolean = shown(answers, index - 1, rowBytes, viewer.slot, target)
				local hidden: boolean = taker.AntiEsp.isHidden(viewer, target)

				if hidden == visible then
					return false,
						`Step {step}: {viewer.key.Name}'s ask about slot {target} gave hidden {hidden} against its answer`
				elseif twin.AntiEsp.isHidden(other, target) ~= hidden then
					return false, `Step {step}: {viewer.key.Name}'s ask about slot {target} differed from the twin's`
				end

				if buffer.readu8(answers.kinds, target) == FREE then
					frees += 1
				else
					local reason: string = taker.AntiEsp.reason(viewer.key, target)
					seen[reason] = (seen[reason] or 0) + 1
				end
			end
		end

		if bytesOf(taker.AntiEsp.answers(taker.viewers)) ~= before then
			return false, `Step {step}'s answers changed with the run's own asks`
		end

		-- Nothing the answers were taken for differs from the twin
		local tests: number, hiddenResults: number, failOpens: number = taker.AntiEsp.counts()
		local twinTests: number, twinHidden: number, twinFailOpens: number = twin.AntiEsp.counts()
		local lying: number, waiting: number = taker.AntiEsp.lying()
		local twinLying: number, twinWaiting: number = twin.AntiEsp.lying()

		if tests ~= twinTests or hiddenResults ~= twinHidden or failOpens ~= twinFailOpens then
			return false, `Step {step}'s counts were {tests}, {hiddenResults}, {failOpens} against the twin's`
		elseif lying ~= twinLying or waiting ~= twinWaiting then
			return false, `Step {step}'s lying counts were {lying} and {waiting} against the twin's`
		end

		for index: number, viewer: any in taker.viewers do
			for _, target: number in asked do
				local reason: string = taker.AntiEsp.reason(viewer.key, target)
				if reason ~= twin.AntiEsp.reason(twin.viewers[index].key, target) then
					return false,
						`Step {step}: {viewer.key.Name}'s pair with slot {target} was {reason} against the twin's`
				end
			end
		end
	end

	-- The seed reached every branch an ask has
	for _, reason: string in REASONS do
		if seen[reason] == nil then
			return false, `No ask left a pair {reason}`
		end
	end

	if frees == 0 or lefts == 0 or reborns == 0 or sleeps == 0 or wakes == 0 then
		return false,
			`The seed gave {frees} free asks, {lefts} left out, {reborns} new lives, {sleeps} sleeps and {wakes} wakes`
	end

	return true, nil
end
