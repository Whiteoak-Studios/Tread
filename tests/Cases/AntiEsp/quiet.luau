--[[
    Through seeded runs, slices and holds, a side that marks each quiet ask
    through AntiEsp.asked and asks the rest ends every step as a twin that
    asks them all does, with every changing ask asked; and asked's refusals
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local SEED: number = 20261118 -- Park and Miller's generator's start, any whole number from 1 below its modulus
local MULTIPLIER: number = 16807
local MODULUS: number = 2147483647
local STEPS: number = 240
local EVENTS: number = 14 -- A change to the world is one of the first five of these, or none
local LEFT_OUT: number = 8 -- One ask in this many is left out of its run
local HOLDS: number = 3 -- One run in this many is held, with a change made inside its hold
local ALONE: number = 12 -- One run in this many has only the captain ask, and only about its mate
local STRAY: number = 21 -- Studs a step moves a body across each axis, centered on 0
local REACH: number = 500 -- Studs from the origin a body may stray to, inside the play bound
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row
local LYING_SHARE: number = 1 -- Seconds, the harness's whole slice, so each slice tests its sleepers first in one order
local RED: number = 1
local BLUE: number = 2
local GREEN: number = 3 -- The captain's and its mate's, which nothing changes
local DELAYS: { number } = { 0.05, 0.1, 0.2 } -- Seconds from one slice to the next, the last past the fail-open time
local SLICINGS: number = 5 -- A step runs no slice for 0 of these, a starved one for 1 and a full one for the rest
local LEAVE_AT: number = STEPS // 3 -- A step whose hold a viewer leaves inside, whatever the seed gives
local RELEASE_AT: number = STEPS // 2 -- The step whose hold releases a body's slot, its pairs still kept

-- The answers' kinds
local FREE: number = 0
local PLAYER: number = 1
local LYING: number = 2
local NPC: number = 3

-- What the wall answers: no ray blocked, every ray blocked, or some by where they end
local OPEN: number = 0
local SOLID: number = 1
local PATTERNS: number = 4 -- The modes a step picks from, the last two both the pattern
local OFFSETS: number = 5

-- Why an ask changes anti-ESP beyond its pair's stamp, each of which must find its quiet bit clear
local CHANGING: { string } = { "first", "stale", "life", "sleep", "wake" }

-- The reasons a pair gives once a test has run on it, so a stale ask finding one found its pair kept
local TESTED: { [string]: boolean } = { Clear = true, Hold = true, FailOpen = true, Hidden = true }

-- Each body by its name and kind, where it starts, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "First", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Second", kind = "Player", at = vector.create(40, 0, 0), sees = true },
	{ name = "Far", kind = "Player", at = vector.create(0, 0, 300), sees = true },
	{ name = "Captain", kind = "Player", at = vector.create(-40, 0, 20), sees = true },
	{ name = "Mate", kind = "Player", at = vector.create(-50, 0, 30), sees = false },
	{ name = "Near", kind = "Player", at = vector.create(0, 0, -30), sees = false },
	{ name = "Wanderer", kind = "Player", at = vector.create(-60, 0, -80), sees = false },
	{ name = "Distant", kind = "Player", at = vector.create(0, 0, -400), sees = false },
	{ name = "Guard", kind = "Npc", at = vector.create(20, 0, -20), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-20, 0, -40), sees = false },
	{ name = "Body", kind = "Body", at = vector.create(30, 0, -60), sees = false },
}

local GONE: string = "Distant" -- Released inside a hold, so its slot is free with its pairs still kept
local SLEEPS: { string } = { "Near", "Wanderer", "Sleeper" } -- The bodies a change may put to sleep or wake
local STILL: { [string]: boolean } = { Captain = true, Mate = true } -- Never moved, nor given a life, team or sleep

-- One harness and the bodies and viewers it holds, built the same on both sides
type Side = {
	harness: any,
	AntiEsp: any,
	Slots: any,
	viewers: { any },
	viewerOf: { [number]: any }, -- Each body's viewer by its slot, for those that see
	slots: { [string]: number },
}

-- What the plain side's last ask about a pair left it with
type Seen = {
	round: number,
	life: number,
	lying: boolean,
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

-- The answers' four buffers as one string, to tell whether two takes gave the same
local function bytesOf(answers: any): string
	return buffer.tostring(answers.kinds)
		.. buffer.tostring(answers.teams)
		.. buffer.tostring(answers.visible)
		.. buffer.tostring(answers.quiet)
end

return function (): (boolean, string | nil)
	local Constants: any = Environment.load(CONSTANTS)
	local rowBytes: number = Constants.SLOTS // BITS
	local free: number = Constants.SLOTS - 1 -- A slot no body takes

	-- 1) The refusals: before start, before any answers, after a slice since them, and a slot with no pair
	local Unstarted: any = Environment.load(HARNESS)
	local ran: boolean, message: any = pcall(Unstarted.AntiEsp.asked, { key = { Name = "Nobody" } }, {}, 0)
	if ran or not string.find(`{message}`, "before AntiEsp.start", 1, true) then
		return false, `asked before start gave {message}`
	end

	local Probe: any = Environment.load(HARNESS)
	local probe: any = Probe.new()
	local probed: number = probe:body("Player", vector.create(0, 0, -20))
	local looker: any = probe:viewer("Looker", nil)

	if pcall(Probe.AntiEsp.asked, looker, { probed }, 1) then
		return false, "asked ran before any answers"
	end

	Probe.AntiEsp.isHidden(looker, probed)
	Probe.AntiEsp.answers({ looker })
	probe:slice(0.1)

	ran, message = pcall(Probe.AntiEsp.asked, looker, { probed }, 1)
	if ran or not string.find(`{message}`, "since the last slice", 1, true) then
		return false, `asked after a slice since the answers gave {message}`
	end

	Probe.AntiEsp.answers({ looker })
	ran, message = pcall(Probe.AntiEsp.asked, looker, { free }, 1)
	if ran or not string.find(`{message}`, `slot {free}`, 1, true) then
		return false, `asked about a slot with no pair gave {message}`
	elseif not pcall(Probe.AntiEsp.asked, looker, { probed }, 1) then
		return false, "asked refused a slot with a pair once the answers were taken again"
	end

	-- 2) Two sides over the same seeded world and slices, one asking everything and one marking its quiet asks
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

	local plain: Side = side()
	local marked: Side = side()

	local function both(change: (built: Side) -> ())
		change(plain)
		change(marked)
	end

	both(function (built: Side)
		built.AntiEsp.setTeam(built.slots.First, RED)
		built.AntiEsp.setTeam(built.slots.Near, RED)
		built.AntiEsp.setTeam(built.slots.Second, BLUE)
		built.AntiEsp.setTeam(built.slots.Wanderer, BLUE)
		built.AntiEsp.setTeam(built.slots.Captain, GREEN)
		built.AntiEsp.setTeam(built.slots.Mate, GREEN)
	end)

	-- Every body's slot, the same on both sides, then the free one, in the order each run asks
	local asked: { number } = {}
	local movable: { number } = {}
	for _, body in BODIES do
		table.insert(asked, plain.slots[body.name])

		if not STILL[body.name] then
			table.insert(movable, plain.slots[body.name])
		end
	end
	table.insert(asked, free)

	local captain: number = plain.slots.Captain
	local mateOnly: { number } = { plain.slots.Mate }
	local nothing: { number } = {}

	-- What the plain side's asks left each pair with, by the viewer's place and the slot, and each slot's new lives
	local lastAsks: { { [number]: Seen } } = {}
	for index: number = 1, #plain.viewers do
		lastAsks[index] = {}
	end

	local lives: { [number]: number } = {}
	for _, slot: number in asked do
		lives[slot] = 0
	end

	-- The round the plain side's asks are in, and whether a slice ran since one last opened
	local round: number = 0
	local sliced: boolean = true

	-- Model changes a hold keeps until its release, as anti-ESP keeps the changes they follow
	local holding: boolean = false
	local pending: { () -> () } = {}
	local function later(update: () -> ())
		if holding then
			table.insert(pending, update)
		else
			update()
		end
	end

	local reached: { [string]: number } = {
		first = 0,
		stale = 0,
		life = 0,
		sleep = 0,
		wake = 0,
		failOpen = 0,
		staleKept = 0,
	}
	local markCount: number = 0
	local teammates: number = 0
	local alones: number = 0
	local leavesHeld: number = 0
	local releasesHeld: number = 0
	local starved: number = 0
	local problem: string? = nil -- The first ask whose quiet bit disagreed with why it changes anti-ESP

	local function leave(index: number)
		both(function (built: Side)
			built.AntiEsp.leave(built.viewers[index].key)
		end)

		later(function ()
			table.clear(lastAsks[index])
		end)

		if holding then
			leavesHeld += 1
		end
	end

	-- One change to the world, the same on both sides, at once or at a hold's release
	local function happen(event: number, slot: number)
		local _, entry: any = plain.Slots.get(slot)

		-- The harness's new life takes every other free slot in turn, which a sleeper can't past the reserve
		if event == 0 and entry.kind ~= "Sleeper" then
			both(function (built: Side)
				built.harness:reborn(slot)
			end)

			later(function ()
				lives[slot] += 1
			end)
		elseif event == 1 then
			local sleeper: number = plain.slots[SLEEPS[roll(#SLEEPS) + 1]]
			local _, lying: any = plain.Slots.get(sleeper)
			local kind: string = lying.kind == "Sleeper" and "Player" or "Sleeper"

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
			leave(roll(#plain.viewers) + 1)
		end
	end

	-- Every answer, reason and count the same on both sides, or what differed
	local function differs(): string?
		if bytesOf(plain.AntiEsp.answers(plain.viewers)) ~= bytesOf(marked.AntiEsp.answers(marked.viewers)) then
			return "the answers differed"
		end

		for index: number, viewer: any in plain.viewers do
			for _, target: number in asked do
				local reason: string = plain.AntiEsp.reason(viewer.key, target)
				local other: string = marked.AntiEsp.reason(marked.viewers[index].key, target)
				if reason ~= other then
					return `{viewer.key.Name}'s pair with slot {target} was {reason} against the marked side's {other}`
				end
			end
		end

		local tests: number, hiddenResults: number, failOpens: number = plain.AntiEsp.counts()
		local markedTests: number, markedHidden: number, markedFailOpens: number = marked.AntiEsp.counts()
		local lying: number, waiting: number = plain.AntiEsp.lying()
		local markedLying: number, markedWaiting: number = marked.AntiEsp.lying()

		if tests ~= markedTests or hiddenResults ~= markedHidden or failOpens ~= markedFailOpens then
			return `the counts were {tests}, {hiddenResults}, {failOpens} against {markedTests}, {markedHidden}, {markedFailOpens}`
		elseif lying ~= markedLying or waiting ~= markedWaiting then
			return `the lying counts were {lying} and {waiting} against {markedLying} and {markedWaiting}`
		end

		return nil
	end

	local marks: { number } = {} -- Reused by every turn, so entries past a turn's count are an earlier turn's

	--[[
	    One run: the marked side's answers taken at its start, a change
	    inside it when it holds, then each viewer's turn, the plain side
	    asking everything and the marked side asking only what isn't quiet,
	    in the walk's order, and taking the rest through asked
	--]]

	local function run(step: number): string?
		local alone: boolean = roll(ALONE) == 0
		local held: boolean = step == LEAVE_AT or step == RELEASE_AT or roll(HOLDS) == 0

		if held then
			both(function (built: Side)
				built.AntiEsp.hold()
			end)
			holding = true
		end

		local answers: any = marked.AntiEsp.answers(marked.viewers)

		if step == RELEASE_AT then
			local gone: number = plain.slots[GONE]
			table.remove(movable, table.find(movable, gone))
			releasesHeld += 1

			both(function (built: Side)
				built.Slots.release(gone)
				built.harness.states[gone] = nil
			end)
		elseif step == LEAVE_AT then
			leave(roll(#plain.viewers) + 1)
		elseif held then
			happen(roll(EVENTS), movable[roll(#movable) + 1])
		end

		if alone and sliced then
			alones += 1
		end

		for index: number, viewer: any in plain.viewers do
			local other: any = marked.viewers[index]
			local own: number? = viewer.slot
			local count: number = 0

			local targets: { number } = asked
			if own == captain then
				targets = mateOnly
			elseif alone then
				targets = nothing
			end

			for _, target: number in targets do
				if target == own then
					continue
				elseif roll(LEFT_OUT) == 0 then
					continue
				end

				local kind: number = buffer.readu8(answers.kinds, target)
				local teammate: boolean = kind == PLAYER
					and own ~= nil
					and buffer.readf64(answers.teams, own * 8) == buffer.readf64(answers.teams, target * 8)
				local byte: number = (index - 1) * rowBytes + target // BITS
				local bit: number = bit32.lshift(1, target % BITS)
				local quiet: boolean = bit32.btest(buffer.readu8(answers.quiet, byte), bit)
				local shown: boolean = kind == FREE
					or kind == NPC
					or teammate
					or bit32.btest(buffer.readu8(answers.visible, byte), bit)

				-- Why the ask changes more than its pair's stamp, from what the plain side's last ask left the pair with
				local why: string = "read"
				if teammate then
					why = "teammate"
					teammates += 1
				elseif kind == PLAYER or kind == LYING then
					if sliced then
						round += 1
						sliced = false
					end

					local lying: boolean = kind == LYING
					local last: Seen? = lastAsks[index][target]
					if last == nil then
						why = "first"
					elseif last.round < round - 1 then
						why = "stale"
					elseif last.life ~= lives[target] then
						why = "life"
					elseif last.lying ~= lying then
						why = lying and "sleep" or "wake"
					else
						why = "kept"
					end

					lastAsks[index][target] = { round = round, life = lives[target], lying = lying }
				end

				local before: string = plain.AntiEsp.reason(viewer.key, target)
				local hidden: boolean = plain.AntiEsp.isHidden(viewer, target)
				if hidden == shown then
					return `{viewer.key.Name}'s ask about slot {target} gave hidden {hidden} against its answer`
				end

				-- A teammate's ask goes as an ask whatever its bit, as the relay sends it
				local failedOpen: boolean = false
				if quiet and not teammate then
					count += 1
					marks[count] = target
					markCount += 1
				else
					local _, _, opened: number = marked.AntiEsp.counts()
					marked.AntiEsp.isHidden(other, target)
					local _, _, failOpens: number = marked.AntiEsp.counts()
					failedOpen = failOpens > opened
				end

				if why == "kept" then
					if failedOpen then
						reached.failOpen += 1
					elseif not quiet and problem == nil then
						problem = `{viewer.key.Name}'s ask about slot {target} only stamped its pair, yet wasn't quiet`
					end
				elseif table.find(CHANGING, why) then
					if quiet and problem == nil then
						problem = `{viewer.key.Name}'s {why} ask about slot {target} was quiet`
					elseif not quiet then
						reached[why] += 1

						if why == "stale" and TESTED[before] then
							reached.staleKept += 1
						end
					end
				end
			end

			marked.AntiEsp.asked(other, marks, count)
		end

		if held then
			both(function (built: Side)
				built.AntiEsp.release()
			end)
			holding = false

			for _, update: () -> () in pending do
				update()
			end
			table.clear(pending)
		end

		return nil
	end

	local now: number = 0

	for step: number = 1, STEPS do
		-- The world changes between runs, the same on both sides
		local event: number = roll(EVENTS)
		local slot: number = movable[roll(#movable) + 1]
		happen(event, slot)

		local stray: vector = vector.create(roll(STRAY) - STRAY // 2, 0, roll(STRAY) - STRAY // 2)
		local position: vector = plain.harness.states[slot].position + stray
		position = vector.create(math.clamp(position.x, -REACH, REACH), 0, math.clamp(position.z, -REACH, REACH))

		both(function (built: Side)
			built.harness:move(slot, position, built.viewerOf[slot])
		end)

		mode = roll(PATTERNS)
		offset = roll(OFFSETS)

		-- No slice, so two runs share a round; a starved slice that tests nothing; or one with time for every test
		local slicing: number = roll(SLICINGS)
		if slicing ~= 0 then
			now += DELAYS[roll(#DELAYS) + 1]
			local budget: number? = nil
			if slicing == 1 then
				budget = 0
				starved += 1
			end

			both(function (built: Side)
				built.harness:slice(now, budget)
			end)
			sliced = true

			if not sameRays(plain.harness.rays, marked.harness.rays) then
				return false, `Step {step}'s slice cast other rays on the marked side`
			end
		end

		local failed: string? = run(step)
		if failed then
			return false, `Step {step}: {failed}`
		end

		local differed: string? = differs()
		if differed then
			return false, `After step {step}, {differed}`
		elseif problem then
			return false, `Step {step}: {problem}`
		end
	end

	-- The seed reached every ask that changes anti-ESP with its quiet bit clear, and marked the rest
	for _, why: string in CHANGING do
		if reached[why] == 0 then
			return false, `No {why} ask was reached`
		end
	end

	if reached.failOpen == 0 or reached.staleKept == 0 then
		return false, `The seed gave {reached.failOpen} fail-opens and {reached.staleKept} stale asks of a kept pair`
	elseif markCount == 0 or teammates == 0 or alones == 0 then
		return false,
			`The seed gave {markCount} marks, {teammates} teammate asks and {alones} runs of the captain alone`
	elseif leavesHeld == 0 or releasesHeld == 0 or starved == 0 then
		return false,
			`The seed gave {leavesHeld} held leaves, {releasesHeld} held releases and {starved} starved slices`
	end

	return true, nil
end
