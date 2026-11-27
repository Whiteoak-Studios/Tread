--[[
    A respawn gives the owner a predicted body again: freeing its slot ends
    the body, puts its rig away and stops its Moves, and its new slot's
    first OwnerState starts a new body there, numbered past that state's
    command, with a rig of its own
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local FIRST: number = 9
local SECOND: number = 14
local GENERATION: number = 1
local TICK: number = 100
local LATER: number = 160 -- The server's tick when the new character is built
local COMMAND: number = 500 -- The new character's first OwnerState's command
local FRAMES: number = 3
local HEADROOM: number = 1e-6 -- How far a float32 Vector3 may sit from the vector it was copied from

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
	rig.own(FIRST, GENERATION)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(FRAMES)
	rig.step()

	if #rig.moves == 0 then
		return false, "The first body sent no Move"
	elseif #spawned ~= 1 or spawned[1].id ~= FIRST or spawned[1].player ~= rig.player then
		return false, `The first body drew {#spawned} rigs, not the local player's in slot {FIRST}`
	end

	-- The game destroys the character, and the slot table frees its slot
	rig.slots({ { slot = FIRST, generation = GENERATION } })

	if handle:getState() ~= nil then
		return false, "The owner still had a state once its slot was freed"
	elseif #despawned ~= 1 or despawned[1] ~= spawned[1] then
		return false, `Freeing the owner's slot told {#despawned} despawns, not 1 with its spawn's Slot`
	elseif #pool.of("release") ~= 1 or pool.of("release")[1].slot ~= FIRST then
		return false, "Freeing the owner's slot didn't put its rig back in the pool"
	end

	local moves: number = #rig.moves
	rig.frames(FRAMES)
	rig.step()

	if #rig.moves ~= moves then
		return false, `With no body the client sent {#rig.moves - moves} Moves`
	end

	-- The new character, in a new slot
	local at: vector = vector.create(30, 60, -10)
	rig.own(SECOND, GENERATION)
	rig.owner(rig.body(at, COMMAND, LATER))

	local state: any = handle:getState()
	if state == nil then
		return false, "The new character's first OwnerState started no body"
	elseif math.abs(state.root.X - at.x) > HEADROOM or math.abs(state.root.Z - at.z) > HEADROOM then
		return false, `The new body stands at {state.root}, not at the new character's {at}`
	end

	rig.frames(FRAMES)
	rig.step()

	local newest: any = rig.moves[#rig.moves]
	local ahead: number = rig.globals.require(rig.tread.Codec.Sequence).difference(newest.command, COMMAND)
	if #rig.moves == moves then
		return false, "The new body sent no Move"
	elseif ahead < 1 or ahead > FRAMES then
		return false, `The new body's Move carried command {newest.command}, not one of the {FRAMES} past {COMMAND}`
	elseif #spawned ~= 2 or spawned[2].id ~= SECOND then
		return false, `The new body drew no rig for slot {SECOND}`
	end

	return true, nil
end
