--[[
    A reveal draws a slot's rig and tells the spawn once: a repeat of it or
    a change of kind keeps the rig and its Slot, the kind changed in place,
    and a hide puts the rig away and tells the despawn with that same Slot
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local SLOT: number = 3
local GENERATION: number = 1
local TICK: number = 50
local FRAMES: number = 12

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	local spawned: { any } = {}
	local despawned: { any } = {}
	handle:onSpawned(function (slot: any, _: any)
		table.insert(spawned, slot)
	end)
	handle:onDespawned(function (slot: any)
		table.insert(despawned, slot)
	end)

	rig.handshake()
	rig.slots({ { slot = SLOT, generation = GENERATION, rig = "A" } })

	local at: vector = vector.create(1, 2, 3)
	local function block(tick: number, kind: string?)
		local reveals: { any } = {}
		if kind then
			reveals = { { slot = SLOT, generation = GENERATION, kind = kind } }
		end

		rig.relay({
			tick = tick,
			reveals = reveals,
			records = { { slot = SLOT, generation = GENERATION, position = at } },
		})
	end

	block(TICK, "Player")
	block(TICK + 1, "Player") -- A pending reveal repeats until it is acknowledged
	block(TICK + 2, "Sleeper")

	if #spawned ~= 1 then
		return false, `A reveal, its repeat and a change of kind told {#spawned} spawns, not 1`
	elseif #pool.of("checkout") ~= 1 then
		return false, `The slot's rig was checked out {#pool.of("checkout")} times, not once`
	elseif spawned[1].kind ~= "Sleeper" then
		return false, `After a change of kind the slot's Slot reads {spawned[1].kind}, not Sleeper`
	end

	rig.frames(FRAMES)

	-- A sleeper is drawn, and the owner's prediction never blocks against it
	if #pool.of("pose") == 0 then
		return false, "The sleeper's rig was never posed"
	elseif #handle._world.bodies ~= 0 then
		return false, "A sleeper was handed to the owner's prediction to block against"
	end

	rig.relay({ tick = TICK + 3, hides = { { slot = SLOT, generation = GENERATION } } })

	if #despawned ~= 0 then
		return false, "A hide put the rig away before a frame brought the render time to it"
	end

	rig.frames(FRAMES)

	local releases: { any } = pool.of("release")
	if #despawned ~= 1 or despawned[1] ~= spawned[1] then
		return false, `The hide told {#despawned} despawns, not 1 with the spawn's Slot`
	elseif #releases ~= 1 or releases[1].slot ~= SLOT then
		return false, `The hide released {#releases} rigs, not slot {SLOT}'s`
	end

	-- A rig put away is posed no more
	local poses: number = #pool.of("pose")
	rig.frames(FRAMES)
	if #pool.of("pose") ~= poses then
		return false, "A rig put away was still posed"
	end

	return true, nil
end
