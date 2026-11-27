--[[
    A death turns a drawn rig into its body's ragdoll, keyed to the body's
    slot with the death's push: the dying slot's despawn and the body's
    spawn are told, the ragdoll is never posed, the body's own reveal draws
    nothing more, and the slot table freeing the body puts it away. The
    owner's own death ragdolls its rig and ends its body
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local DYING: number = 3
local BODY: number = 20
local OWN_BODY: number = 21
local GENERATION: number = 1
local TICK: number = 50
local FRAMES: number = 6
local PUSH: vector = vector.create(1, 0, 0)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	local spawned: { { slot: any, rig: any } } = {}
	local despawned: { any } = {}
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
	end)
	handle:onDespawned(function (slot: any)
		table.insert(despawned, slot)
	end)

	rig.handshake()
	rig.slots({ { slot = DYING, generation = GENERATION, rig = "A" } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = DYING, generation = GENERATION, kind = "Npc" } },
		records = { { slot = DYING, generation = GENERATION, position = vector.create(1, 2, 3) } },
	})
	rig.frames(FRAMES)

	-- The server writes the body's slot table entry, then the death
	rig.slots({ { slot = BODY, generation = GENERATION, rig = "A" } })
	rig.death(DYING, GENERATION, BODY, GENERATION, PUSH)

	local ragdolls: { any } = pool.of("ragdoll")
	if #ragdolls ~= 1 or ragdolls[1].slot ~= DYING or ragdolls[1].body ~= BODY then
		return false, `The death made {#ragdolls} ragdolls, not slot {DYING}'s keyed to slot {BODY}`
	elseif ragdolls[1].push ~= PUSH then
		return false, `The ragdoll was pushed along {ragdolls[1].push}, not the death's {PUSH}`
	elseif #despawned ~= 1 or despawned[1] ~= spawned[1].slot then
		return false, "The death told no despawn of the dying slot's Slot"
	elseif #spawned ~= 2 or spawned[2].slot.id ~= BODY or spawned[2].slot.kind ~= "Body" then
		return false, `The death told no spawn of a Body in slot {BODY}`
	elseif spawned[2].rig ~= spawned[1].rig then
		return false, "The body's spawn handed another rig than the one that died"
	end

	local poses: number = #pool.of("pose")
	rig.relay({
		tick = TICK + 1,
		reveals = { { slot = BODY, generation = GENERATION, kind = "Body" } },
		records = { { slot = BODY, generation = GENERATION, position = vector.create(1, 2, 3) } },
	})
	rig.frames(FRAMES)

	if #spawned ~= 2 or #pool.of("checkout") ~= 1 then
		return false, "The body's reveal checked out or told another rig, though its ragdoll is drawn"
	elseif #pool.of("pose") ~= poses then
		return false, "A ragdoll was posed"
	elseif #handle._world.bodies ~= 0 then
		return false, "A body was handed to the owner's prediction to block against"
	end

	rig.slots({ { slot = BODY, generation = GENERATION } })

	local releases: { any } = pool.of("release")
	if #releases ~= 1 or releases[1].slot ~= BODY then
		return false, `Freeing the body's slot released {#releases} rigs, not slot {BODY}'s`
	elseif #despawned ~= 2 or despawned[2] ~= spawned[2].slot then
		return false, "Freeing the body's slot told no despawn of its Slot"
	end

	-- The owner's own death, whose body is never revealed to it
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(1)

	rig.slots({ { slot = OWN_BODY, generation = GENERATION, rig = "A" } })
	rig.death(OWN, GENERATION, OWN_BODY, GENERATION, vector.zero)

	local own: any = pool.of("ragdoll")[2]
	if own == nil or own.slot ~= OWN or own.body ~= OWN_BODY then
		return false, `The owner's death ragdolled no rig of slot {OWN} into slot {OWN_BODY}`
	elseif handle:getState() ~= nil then
		return false, "The owner still had a state after its death"
	end

	rig.slots({ { slot = OWN, generation = GENERATION }, { slot = OWN_BODY, generation = GENERATION } })

	local last: any = pool.of("release")[2]
	if last == nil or last.slot ~= OWN_BODY then
		return false, "Freeing the owner's body's slot, which was never revealed, left its ragdoll out"
	end

	return true, nil
end
