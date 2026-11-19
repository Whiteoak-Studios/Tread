--[[
    Changes made inside a hold change nothing until the release, which
    makes them in arrival order, as if made after the round's asks; a
    slice, a second hold and a release with no hold out are refused
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LYING_SHARE: number = 1 -- Seconds, the harness's whole slice, so each slice tests its sleepers first in one order
local RED: number = 1
local BLUE: number = 2
local FRESH_AT: vector = vector.create(-30, 0, -10) -- Where the body made inside the hold stands
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row

-- The answers' kinds
local FREE: number = 0
local PLAYER: number = 1
local LYING: number = 2
local NPC: number = 3

-- What the wall answers: no ray blocked, every ray blocked, or some by where they end
local OPEN: number = 0
local SOLID: number = 1
local PATTERN: number = 2
local OFFSETS: number = 5

-- The steps before the hold and after it, each its wall, its pattern's offset, its slice's delay and budget
local BEFORE: { { number } } = {
	{ OPEN, 0, 0.1, 1 },
	{ PATTERN, 1, 0.1, 1 },
	{ SOLID, 0, 0.6, 1 },
	{ PATTERN, 3, 0.1, 1 },
	{ SOLID, 0, 0.2, 0 },
}
local AFTER: { { number } } = {
	{ PATTERN, 2, 0.1, 1 },
	{ SOLID, 0, 0.2, 1 },
	{ OPEN, 0, 0.6, 1 },
	{ PATTERN, 4, 0.1, 1 },
}

-- Each body by its name and kind, where it starts, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "First", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "Second", kind = "Player", at = vector.create(40, 0, 0), sees = true },
	{ name = "Mate", kind = "Player", at = vector.create(0, 0, -30), sees = false },
	{ name = "Enemy", kind = "Player", at = vector.create(-50, 0, -60), sees = false },
	{ name = "Napper", kind = "Player", at = vector.create(20, 0, -40), sees = false },
	{ name = "Changing", kind = "Player", at = vector.create(60, 0, -20), sees = false },
	{ name = "Reborn", kind = "Player", at = vector.create(-10, 0, 70), sees = false },
	{ name = "Doomed", kind = "Player", at = vector.create(0, 0, -300), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-20, 0, -40), sees = false },
	{ name = "Guard", kind = "Npc", at = vector.create(20, 0, -20), sees = false },
}

-- One harness and the bodies and viewers it holds, built the same on both sides
type Side = {
	harness: any,
	AntiEsp: any,
	Slots: any,
	viewers: { any },
	slots: { [string]: number },
	fresh: number?, -- The body made inside the hold, once it is
}

-- The answers' three buffers as one string, to tell whether two takes gave the same
local function bytesOf(answers: any): string
	return buffer.tostring(answers.kinds) .. buffer.tostring(answers.teams) .. buffer.tostring(answers.visible)
end

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

return function (): (boolean, string | nil)
	-- Before start, neither a hold nor the answers run
	local Unstarted: any = Environment.load(HARNESS)
	if pcall(Unstarted.AntiEsp.hold) or pcall(Unstarted.AntiEsp.answers, {}) then
		return false, "A hold or the answers ran before AntiEsp.start"
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
			slots = {},
			fresh = nil,
		}

		for _, body in BODIES do
			local slot: number = harness:body(body.kind, body.at)
			built.slots[body.name] = slot

			if body.sees then
				table.insert(built.viewers, harness:viewer(body.name, slot))
			end
		end

		table.insert(built.viewers, harness:viewer("Eye", nil))
		built.AntiEsp.setTeam(built.slots.First, RED)
		built.AntiEsp.setTeam(built.slots.Mate, RED)
		built.AntiEsp.setTeam(built.slots.Second, BLUE)

		return built
	end

	local held: Side = side()
	local plain: Side = side()

	-- Every body's slot, the same on both sides
	local asked: { number } = {}
	for _, body in BODIES do
		table.insert(asked, held.slots[body.name])
	end

	-- Each viewer's asks in the walk's order, every answer kept in that order
	local function ask(built: Side, slots: { number }): { boolean }
		local answers: { boolean } = {}

		for _, viewer: any in built.viewers do
			for _, slot: number in slots do
				if slot ~= viewer.slot then
					table.insert(answers, built.AntiEsp.isHidden(viewer, slot))
				end
			end
		end

		return answers
	end

	-- Every reason anti-ESP gives a viewer and slot, in one string
	local function reasonsOf(built: Side, slots: { number }): string
		local reasons: { string } = {}

		for _, viewer: any in built.viewers do
			for _, slot: number in slots do
				table.insert(reasons, built.AntiEsp.reason(viewer.key, slot))
			end
		end

		return table.concat(reasons, " ")
	end

	-- One step on both sides: its wall, a slice, then a run, with whatever differs between them named
	local function step(entry: { number }, now: number, slots: { number }): string?
		mode = entry[1]
		offset = entry[2]

		for _, built: Side in { held, plain } do
			built.harness:slice(now, entry[4])
		end

		if not sameRays(held.harness.rays, plain.harness.rays) then
			return "a slice cast other rays"
		end

		local heldAnswers: { boolean } = ask(held, slots)
		local plainAnswers: { boolean } = ask(plain, slots)

		for index: number, hidden: boolean in heldAnswers do
			if plainAnswers[index] ~= hidden then
				return `ask {index} answered hidden {hidden} against {plainAnswers[index]}`
			end
		end

		return nil
	end

	local now: number = 0
	for index: number, entry: { number } in BEFORE do
		now += entry[3]

		local differed: string? = step(entry, now, asked)
		if differed then
			return false, `Before the hold, step {index}: {differed}`
		end
	end

	-- The round's answers, taken at its start, and every reason as it stands
	local answers: any = held.AntiEsp.answers(held.viewers)
	local before: string = bytesOf(answers)
	local reasons: string = reasonsOf(held, asked)

	held.AntiEsp.hold()

	if pcall(held.AntiEsp.hold) then
		return false, "A second hold was taken while one was out"
	elseif pcall(held.AntiEsp.run, 1, now) then
		return false, "A slice ran inside a hold"
	end

	local second: any = held.viewers[2]

	-- Every change a game, the server and the slot table make, in an order where order matters
	local changes: { { name: string, run: (built: Side) -> () } } = {
		{
			name = "the enemy's team twice",
			run = function (built: Side)
				built.AntiEsp.setTeam(built.slots.Enemy, RED)
				built.AntiEsp.setTeam(built.slots.Enemy, BLUE)
			end,
		},
		{
			name = "the teammate's team taken away",
			run = function (built: Side)
				built.AntiEsp.setTeam(built.slots.Mate, nil)
			end,
		},
		{
			name = "a team given before a new life",
			run = function (built: Side)
				built.AntiEsp.setTeam(built.slots.Changing, RED)
				built.harness:reborn(built.slots.Changing)
			end,
		},
		{
			name = "a team given after a new life",
			run = function (built: Side)
				built.harness:reborn(built.slots.Reborn)
				built.AntiEsp.setTeam(built.slots.Reborn, RED)
			end,
		},
		{
			name = "a viewer's own body taking a new life",
			run = function (built: Side)
				built.harness:reborn(built.slots.First)
			end,
		},
		{
			name = "a player falling asleep",
			run = function (built: Side)
				built.Slots.setEntry(built.slots.Napper, { kind = "Sleeper", rig = "A" })
			end,
		},
		{
			name = "a viewer's own body moved",
			run = function (built: Side)
				built.AntiEsp.moved(built.slots.Second)
			end,
		},
		{
			name = "a body released",
			run = function (built: Side)
				built.Slots.release(built.slots.Doomed)
				built.harness.states[built.slots.Doomed] = nil
			end,
		},
		{
			name = "a body made",
			run = function (built: Side)
				built.fresh = built.harness:body("Player", FRESH_AT)
			end,
		},
		{
			name = "a viewer leaving",
			run = function (built: Side)
				built.AntiEsp.leave(built.viewers[2].key)
			end,
		},
	}

	for _, change in changes do
		change.run(held)

		answers = held.AntiEsp.answers(held.viewers)
		if bytesOf(answers) ~= before then
			return false, `Inside the hold, {change.name} changed the answers`
		elseif reasonsOf(held, asked) ~= reasons then
			return false, `Inside the hold, {change.name} changed a reason`
		end
	end

	local fresh: number = held.fresh :: number
	local withFresh: { number } = table.clone(asked)
	table.insert(withFresh, fresh)

	-- The round's asks, replayed inside the hold, give the answers taken at its start, which still hold after them
	local replayed: { boolean } = {}
	local place: number = 0
	local rowBytes: number = buffer.len(answers.visible) // #held.viewers

	for row: number, viewer: any in held.viewers do
		for _, slot: number in withFresh do
			if slot == viewer.slot then
				continue
			end

			local hidden: boolean = held.AntiEsp.isHidden(viewer, slot)
			table.insert(replayed, hidden)
			place += 1

			local kind: number = buffer.readu8(answers.kinds, slot)
			local own: number? = viewer.slot
			local teammate: boolean = kind == PLAYER
				and own ~= nil
				and buffer.readf64(answers.teams, own * 8) == buffer.readf64(answers.teams, slot * 8)
			local byte: number = buffer.readu8(answers.visible, (row - 1) * rowBytes + slot // BITS)
			local shown: boolean = kind == FREE
				or kind == NPC
				or teammate
				or bit32.btest(byte, bit32.lshift(1, slot % BITS))

			if hidden == shown then
				return false, `The replayed ask {place}, {viewer.key.Name} about slot {slot}, differed from its answer`
			end
		end
	end

	if bytesOf(held.AntiEsp.answers(held.viewers)) ~= before then
		return false, "The replayed asks changed the answers inside the hold"
	end

	-- Without a hold the same asks come first, then the same changes, each made at once
	local plainAnswers: { boolean } = ask(plain, withFresh)
	for index: number, hidden: boolean in replayed do
		if plainAnswers[index] ~= hidden then
			return false, `The held side's replayed ask {index} answered hidden {hidden} against the plain side's`
		end
	end

	for _, change in changes do
		change.run(plain)
	end

	if plain.fresh ~= fresh then
		return false, `The body made inside the hold took slot {fresh}, and on the plain side {plain.fresh}`
	elseif bytesOf(plain.AntiEsp.answers(plain.viewers)) == before then
		return false, "The changes made with no hold out changed nothing at once"
	end

	held.AntiEsp.release()

	if pcall(held.AntiEsp.release) then
		return false, "A release ran with no hold out"
	end

	-- The release made the changes in order: the last team given counts, and a team stays with the life it was for
	answers = held.AntiEsp.answers(held.viewers)
	local function teamOf(slot: number): number?
		local team: number = buffer.readf64(answers.teams, slot * 8)
		if team ~= team then
			return nil
		end

		return team
	end

	if teamOf(held.slots.Enemy) ~= BLUE or teamOf(held.slots.Mate) ~= nil then
		return false, "The release lost the order of the teams given inside the hold"
	elseif teamOf(held.slots.Changing) ~= nil or teamOf(held.slots.Reborn) ~= RED then
		return false, "A team given inside the hold went to another life than the one it was given for"
	elseif
		buffer.readu8(answers.kinds, held.slots.Napper) ~= LYING or buffer.readu8(answers.kinds, fresh) ~= PLAYER
	then
		return false, "The release didn't make the slot table's changes"
	elseif buffer.readu8(answers.kinds, held.slots.Doomed) ~= FREE then
		return false, "The released body's slot wasn't free after the release"
	elseif held.AntiEsp.reason(second.key, held.slots.Mate) ~= "Untested" then
		return false, "The viewer that left inside the hold kept its pairs past the release"
	end

	-- Both sides now keep the same: every answer, reason and count, and every step after
	local function same(when: string): string?
		if bytesOf(held.AntiEsp.answers(held.viewers)) ~= bytesOf(plain.AntiEsp.answers(plain.viewers)) then
			return `{when}, the answers differed`
		elseif reasonsOf(held, withFresh) ~= reasonsOf(plain, withFresh) then
			return `{when}, a reason differed`
		end

		local tests: number, hidden: number, failOpens: number = held.AntiEsp.counts()
		local plainTests: number, plainHidden: number, plainFailOpens: number = plain.AntiEsp.counts()
		local lying: number, waiting: number = held.AntiEsp.lying()
		local plainLying: number, plainWaiting: number = plain.AntiEsp.lying()

		if tests ~= plainTests or hidden ~= plainHidden or failOpens ~= plainFailOpens then
			return `{when}, the counts were {tests}, {hidden}, {failOpens} against {plainTests}, {plainHidden}, {plainFailOpens}`
		elseif lying ~= plainLying or waiting ~= plainWaiting then
			return `{when}, the lying counts were {lying} and {waiting} against {plainLying} and {plainWaiting}`
		end

		return nil
	end

	local differed: string? = same("After the release")
	if differed then
		return false, differed
	end

	for index: number, entry: { number } in AFTER do
		now += entry[3]

		differed = step(entry, now, withFresh) or same(`After step {index} past the release`)
		if differed then
			return false, `After the release, step {index}: {differed}`
		end
	end

	return true, nil
end
