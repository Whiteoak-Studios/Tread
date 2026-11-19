--[[
    A frozen body's reveal tells its spawn only in the frame whose pose
    moves the kept rig, after the frame's end, with that same rig. Hidden
    again or dead before that pose, it tells no spawn or despawn of its own
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3 -- Hidden, shown and hidden again
local DIES: number = 4 -- Dies between its reveal and its first pose
local BODY: number = 20 -- The slot its death names its body by
local GENERATION: number = 2
local TICK: number = 50
local RELAY: number = 20 -- Relay ticks a second, the example's
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local LONG: number = 1 -- Seconds of one frame that takes the render time past a reveal and the hide after it at once
local STOOD: vector = vector.create(100, 5, 200) -- Where each player is first drawn, and so frozen
local SHOWN: vector = vector.create(40, 5, -30) -- Where the server shows it again

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	-- The stand-in's frame end writes nothing down, so the case writes each one down beside the pool's calls, and each
	-- spawn told beside them
	rigs.frame = function (_: any)
		table.insert(pool.calls, { member = "frame" })
	end

	local spawned: { { slot: any, rig: any } } = {}
	local despawned: { any } = {}
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
		table.insert(pool.calls, { member = "spawned", slot = slot.id })
	end)
	handle:onDespawned(function (slot: any)
		table.insert(despawned, slot)
	end)

	local now: number = TICK -- The relay tick the server writes its next block at

	-- Runs frames of a relay tick each, the server's tick moving on with them
	local function run(frames: number)
		rig.frames(frames)
		now += frames
	end

	local function reveal(slot: number, at: vector)
		rig.relay({
			tick = now,
			reveals = { { slot = slot, generation = GENERATION, kind = "Player" } },
			records = { { slot = slot, generation = GENERATION, position = at, word = rig.word({}) } },
		})
	end

	local function hide(slot: number, culled: boolean)
		rig.relay({ tick = now, hides = { { slot = slot, generation = GENERATION, culled = culled } } })
	end

	-- A slot's reveal and then its hide, with one frame that passes them both, so no pose comes between them
	local function flicker(slot: number, culled: boolean)
		reveal(slot, SHOWN)
		now += 1
		hide(slot, culled)
		rig.frames(1, LONG)
		now += LONG * RELAY
	end

	rig.handshake()
	rig.slots({
		{ slot = OTHER, generation = GENERATION, rig = "A", player = other },
		{ slot = DIES, generation = GENERATION, rig = "A" },
	})

	-- Both players drawn, then hidden by anti-ESP, so each leaves a frozen body
	reveal(OTHER, STOOD)
	reveal(DIES, STOOD)
	run(SETTLE)
	hide(OTHER, true)
	hide(DIES, true)
	run(SETTLE)

	if #spawned ~= 2 or #despawned ~= 2 or #pool.of("freeze") ~= 2 or #pool.of("release") ~= 0 then
		return false, "The two players' hides anti-ESP made left no two frozen bodies"
	end

	local kept: any = spawned[1].rig
	if spawned[1].slot.id ~= OTHER then
		return false, `The first spawn was slot {spawned[1].slot.id}'s, not slot {OTHER}'s`
	end

	-- 1) The reveal's arrival takes the kept rig back with no checkout, no new item in its hands, and no spawn told
	reveal(OTHER, SHOWN)
	if #pool.of("checkout") ~= 2 or #pool.of("hold") ~= 0 then
		return false, "A frozen body's reveal checked a rig out or put an item in its hands"
	elseif #spawned ~= 2 then
		return false, "A frozen body's reveal told its spawn when it arrived, before any pose moved the rig"
	end

	-- 2) The spawn comes in the frame of the slot's first pose, after the frame's end has moved the rig there. The
	-- pool's calls are cleared before each frame, so from here on each count is of the calls since the last clear
	local frames: number = 0
	while #spawned == 2 and frames < SETTLE do
		table.clear(pool.calls)
		run(1)
		frames += 1

		local posed: boolean = #pool.of("pose") > 0
		if posed ~= (#spawned == 3) then
			return false, `A frame posed the kept rig ({posed}) and told its spawn ({#spawned == 3}), which go together`
		end
	end

	local calls: { any } = pool.calls
	local shown: any = spawned[3]
	if shown == nil then
		return false, `{SETTLE} frames after its reveal the kept rig's spawn was never told`
	elseif shown.rig ~= kept or shown.slot.id ~= OTHER or shown.slot.kind ~= "Player" or shown.slot.player ~= other then
		return false, "The spawn after the reveal handed another rig than the frozen body's, or another slot's Slot"
	elseif calls[#calls].member ~= "spawned" or calls[#calls - 1].member ~= "frame" then
		return false, "The kept rig's spawn was told before the pool's frame end had moved the rig"
	elseif pool.of("pose")[1].position ~= SHOWN or pool.of("pose")[1].rig ~= kept then
		return false, `The kept rig's first pose put it at {pool.of("pose")[1].position}, not {SHOWN}`
	elseif #despawned ~= 2 or #pool.of("checkout") ~= 0 then
		return false, "The kept rig's spawn came with a despawn or a checkout"
	end

	-- Spawned again, its next hide anti-ESP made freezes it and tells its despawn like the first
	run(SETTLE)
	hide(OTHER, true)
	run(SETTLE)
	if #despawned ~= 3 or despawned[3] ~= shown.slot or #pool.of("release") ~= 0 then
		return false, "A kept rig spawned again and hidden again told no despawn of its new Slot, or was given back"
	end

	-- 3) Shown and hidden again by anti-ESP before any pose, it stays frozen and tells nothing
	table.clear(pool.calls)
	flicker(OTHER, true)

	local again: { any } = pool.of("freeze")
	if #pool.of("pose") ~= 0 then
		return false, "The frame that passed the reveal and its hide posed the rig, so no hide before a pose is tested"
	elseif #again ~= 1 or not again[1].frozen or #pool.of("release") ~= 0 then
		return false, `A kept rig hidden again before its first pose was frozen {#again} times, or given back`
	elseif #spawned ~= 3 or #despawned ~= 3 then
		return false, "A kept rig hidden again before its first pose told a spawn or a despawn"
	end

	-- 4) Shown and hidden before any pose by a hide anti-ESP didn't make, it goes back to the pool and tells nothing
	flicker(OTHER, false)

	local releases: { any } = pool.of("release")
	if #releases ~= 1 or releases[1].slot ~= OTHER or releases[1].rig ~= kept then
		return false, `A kept rig's hide anti-ESP didn't make released {#releases} rigs, not slot {OTHER}'s`
	elseif #spawned ~= 3 or #despawned ~= 3 or #pool.of("freeze") ~= 1 then
		return false, "A kept rig given back before its first pose told a spawn or a despawn, or was frozen again"
	end

	-- 5) Shown and dead before any pose, its rig becomes its body's: the body's spawn alone is told
	local dying: any = spawned[2].rig
	reveal(DIES, SHOWN)
	rig.slots({ { slot = BODY, generation = GENERATION, rig = "A" } })
	rig.death(DIES, GENERATION, BODY, GENERATION, vector.zero)

	local ragdolls: { any } = pool.of("ragdoll")
	local lying: any = spawned[4]
	if #ragdolls ~= 1 or ragdolls[1].slot ~= DIES or ragdolls[1].body ~= BODY or ragdolls[1].rig ~= dying then
		return false, `A kept rig's death before its first pose made {#ragdolls} ragdolls, not its own`
	elseif lying == nil or lying.slot.id ~= BODY or lying.slot.kind ~= "Body" or lying.rig ~= dying then
		return false, "A kept rig's death told no spawn of its body with that rig"
	elseif #despawned ~= 3 then
		return false, "A kept rig's death told a despawn of a spawn that was never told"
	end

	-- Its body is put away as any is, with the despawn its spawn earned
	rig.slots({ { slot = BODY, generation = GENERATION } })
	if #despawned ~= 4 or despawned[4] ~= lying.slot then
		return false, "Freeing the body's slot told no despawn of its Slot"
	end

	return true, nil
end
