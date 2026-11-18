--[[
    Each end of a frozen body gives its rig back and tells no second
    despawn: a hide's copy anti-ESP didn't make, its slot freed or renewed,
    its death, the render distance, a spectate's start, and a clip played
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local COPIED: number = 3 -- Ended by a later copy of its hide that anti-ESP didn't make
local FREED: number = 4 -- By its slot freed
local RENEWED: number = 5 -- By its slot given a new life
local DIED: number = 6 -- By its death
local FAR: number = 7 -- By the render distance drawn in past where it stands
local SPECTATED: number = 8 -- By a spectate's start, both of them
local ALSO: number = 9
local PLAYED: number = 10 -- Frozen once the spectate has ended, and ended by a clip played
local TARGET: number = 14 -- The spectate's target, and the clip's
local BODY: number = 20 -- The slot the death names its body by
local GENERATION: number = 1
local TICK: number = 50
local KEYFRAME: number = 900 -- The clip's keyframe's tick
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local NEARER: number = 300 -- Studs the render distance is drawn in to, between the bodies' places

-- Where each player is drawn and so frozen, studs from an eye at the origin
local PLACES: { [number]: vector } = {
	[COPIED] = vector.create(10, 0, 0),
	[FREED] = vector.create(20, 0, 0),
	[RENEWED] = vector.create(30, 0, 0),
	[DIED] = vector.create(40, 0, 0),
	[FAR] = vector.create(400, 0, 0),
	[SPECTATED] = vector.create(50, 0, 0),
	[ALSO] = vector.create(60, 0, 0),
}

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local Record: any = rig.globals.require(rig.tread.Codec.Record)

	local spawns: number = 0
	local despawns: number = 0
	handle:onSpawned(function (_: any, _: any)
		spawns += 1
	end)
	handle:onDespawned(function (_: any)
		despawns += 1
	end)

	local now: number = TICK -- The relay tick the server writes its next block at

	-- Runs frames of a relay tick each, the server's tick moving on with them
	local function run(frames: number)
		rig.frames(frames)
		now += frames
	end

	-- Draws players at their places, then hides each with a hide anti-ESP made, so each leaves a frozen body
	local function freeze(places: { [number]: vector })
		local reveals: { any } = {}
		local records: { any } = {}
		local hides: { any } = {}
		for slot: number, at: vector in places do
			table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
			table.insert(records, { slot = slot, generation = GENERATION, position = at, word = rig.word({}) })
			table.insert(hides, { slot = slot, generation = GENERATION, culled = true })
		end

		rig.relay({ tick = now, reveals = reveals, records = records })
		run(SETTLE)
		rig.relay({ tick = now, hides = hides })
		run(SETTLE)
	end

	-- Why the rigs released so far, the frozen bodies told and the spawns told aren't the slots and the counts given
	local function wrong(ended: { number }, bodies: number): string?
		local releases: { any } = pool.of("release")
		local gone: { [number]: boolean } = {}
		for _, call: any in releases do
			gone[call.slot] = true
		end

		for _, slot: number in ended do
			if not gone[slot] then
				return `slot {slot}'s frozen body stayed out of the pool`
			end
		end

		if #releases ~= #ended then
			return `{#releases} rigs went back to the pool, not {#ended}`
		elseif despawns ~= bodies or spawns ~= bodies then
			return `{spawns} spawns and {despawns} despawns were told, not the {bodies} the bodies' own`
		end

		return nil
	end

	local entries: { any } = { { slot = TARGET, generation = GENERATION, rig = "A" } }
	for _, slot: number in { COPIED, FREED, RENEWED, DIED, FAR, SPECTATED, ALSO, PLAYED } do
		table.insert(entries, { slot = slot, generation = GENERATION, rig = "A" })
	end

	rig.handshake()
	rig.slots(entries)
	freeze(PLACES)

	local bodies: number = 7
	local ended: { number } = {}
	local problem: string? = wrong(ended, bodies)
	if problem or #pool.of("freeze") ~= bodies then
		return false, `Seven players' hides anti-ESP made left no seven frozen bodies: {problem}`
	end

	-- 1) A later copy of the hide, which the viewer hasn't acknowledged, says anti-ESP hides it no more
	rig.relay({ tick = now, hides = { { slot = COPIED, generation = GENERATION, culled = false } } })
	table.insert(ended, COPIED)
	problem = wrong(ended, bodies)
	if problem then
		return false, `After a copy of the hide anti-ESP didn't make, {problem}`
	end

	-- 2) The slot table frees the slot, or gives it a new life
	rig.slots({ { slot = FREED, generation = GENERATION } })
	rig.slots({ { slot = RENEWED, generation = GENERATION + 1, rig = "A" } })
	table.insert(ended, FREED)
	table.insert(ended, RENEWED)
	problem = wrong(ended, bodies)
	if problem then
		return false, `After a slot was freed and another given a new life, {problem}`
	end

	-- 3) Its death, whose body takes no rig from a frozen body
	rig.slots({ { slot = BODY, generation = GENERATION, rig = "A" } })
	rig.death(DIED, GENERATION, BODY, GENERATION, vector.zero)
	table.insert(ended, DIED)
	problem = wrong(ended, bodies)
	if problem or #pool.of("ragdoll") ~= 0 then
		return false, `After a frozen body's death, {problem or "its rig was ragdolled"}`
	end

	-- 4) The render distance drawn in past where one stands, checked at the next frame
	handle:setRenderDistance(NEARER)
	run(1)
	table.insert(ended, FAR)
	problem = wrong(ended, bodies)
	if problem then
		return false, `After the render distance came in to {NEARER} studs, {problem}`
	end

	-- 5) A spectate's start ends every one left
	rig.send("Spectate", Record.id(TARGET, GENERATION), now)
	table.insert(ended, SPECTATED)
	table.insert(ended, ALSO)
	problem = wrong(ended, bodies)
	if problem then
		return false, `After a spectate's start, {problem}`
	end

	-- 6) A clip played ends one frozen since the spectate ended, and the clip's end draws none again
	rig.send("Spectate", nil, now)
	freeze({ [PLAYED] = vector.create(70, 0, 0) })
	bodies += 1
	problem = wrong(ended, bodies)
	if problem or #pool.of("freeze") ~= bodies then
		return false, `A player hidden by anti-ESP once the spectate ended left no frozen body: {problem}`
	end

	local clip: any = Clip.new(rig)
	Clip.log(rig)
	local playback: any = handle:play({
		clip.keyframe({ tick = KEYFRAME }),
		clip.frame({
			tick = KEYFRAME,
			owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, KEYFRAME), lag = 0 },
		}),
	})
	table.insert(ended, PLAYED)
	problem = wrong(ended, bodies)
	if problem then
		return false, `After a clip began to play, {problem}`
	end

	local checkouts: number = #pool.of("checkout")
	playback:destroy()
	run(SETTLE)
	if #pool.of("checkout") ~= checkouts or spawns ~= bodies then
		return false, "The clip's end drew a frozen body again"
	end

	return true, nil
end
