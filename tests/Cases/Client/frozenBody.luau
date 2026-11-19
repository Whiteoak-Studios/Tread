--[[
    A hide anti-ESP made leaves a player's rig out as a frozen body: the
    pool freezes it and keeps it, its held item stays, the despawn is told
    once, and the slot is posed and blocked against no more
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local ITEM: number = 7 -- The held item the player is revealed with
local AT: vector = vector.create(100, 5, 200)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	local spawned: { { slot: any, rig: any } } = {}
	local despawned: { any } = {}
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
	end)
	handle:onDespawned(function (slot: any)
		table.insert(despawned, slot)
	end)

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		looks = { { slot = OTHER, generation = GENERATION, held = { item = ITEM } } },
		records = { { slot = OTHER, generation = GENERATION, position = AT, word = rig.word({}) } },
	})
	rig.frames(SETTLE)

	if #spawned ~= 1 or #pool.of("pose") == 0 or #handle._world.bodies ~= 1 then
		return false, "The revealed player wasn't drawn and handed to the owner's prediction before its hide"
	end

	-- The hide waits for the render time, as any does
	rig.relay({ tick = TICK + SETTLE, hides = { { slot = OTHER, generation = GENERATION, culled = true } } })
	if #despawned ~= 0 or #pool.of("freeze") ~= 0 then
		return false, "A hide anti-ESP made froze the rig before a frame brought the render time to it"
	end

	rig.frames(SETTLE)

	local freezes: { any } = pool.of("freeze")
	if #freezes ~= 1 or freezes[1].slot ~= OTHER or freezes[1].rig ~= spawned[1].rig or not freezes[1].frozen then
		return false, `The hide anti-ESP made froze {#freezes} rigs, not slot {OTHER}'s`
	elseif #pool.of("release") ~= 0 then
		return false, "The hide anti-ESP made gave the player's rig back to the pool"
	elseif #pool.of("hold") ~= 1 then
		return false, `The frozen body's hands were given {#pool.of("hold") - 1} more items, where its own stays`
	elseif #despawned ~= 1 or despawned[1] ~= spawned[1].slot then
		return false, `The hide told {#despawned} despawns, not 1 with the spawn's Slot`
	end

	-- A frozen body is posed no more, is no body to block against, and tells nothing again
	local poses: number = #pool.of("pose")
	rig.frames(SETTLE)

	if #pool.of("pose") ~= poses then
		return false, "A frozen body was still posed"
	elseif #handle._world.bodies ~= 0 then
		return false, "A frozen body was handed to the owner's prediction to block against"
	elseif #despawned ~= 1 or #spawned ~= 1 or #pool.of("release") ~= 0 then
		return false, "A frozen body left standing told a spawn or a despawn, or went back to the pool"
	end

	return true, nil
end
