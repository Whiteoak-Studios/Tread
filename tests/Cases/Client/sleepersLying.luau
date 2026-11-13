--[[
    A sleeper and a body first met by their reveals are drawn lying, in the
    Downed posture with no aim pitch whatever their records hold, and are
    never handed to the owner's prediction to block against; a player who
    falls asleep in view lies down in the same rig
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local GENERATION: number = 1
local SLEEPER: number = 11
local BODY: number = 12
local PLAYER: number = 13
local TICK: number = 50
local FRAMES: number = 6
local AT: vector = vector.create(3, 0, -4)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local rigs: any = handle._rigs

	-- The posture each slot was last posed in, and its aim pitch
	local postures: { [number]: string } = {}
	local pitches: { [number]: number } = {}
	local pose: any = rigs.pose
	rigs.pose = function (self: any, slot: number, state: any, distance: number, pitch: number)
		postures[slot] = state.posture
		pitches[slot] = pitch
		pose(self, slot, state, distance, pitch)
	end

	local spawned: { any } = {}
	handle:onSpawned(function (slot: any, _: any)
		table.insert(spawned, slot)
	end)

	-- Records that say standing and pitched up, which a sleeper and a body are drawn lying through
	local word: number = rig.word({ posture = "Stand", sprint = true })
	local kinds: { [number]: string } = { [SLEEPER] = "Sleeper", [BODY] = "Body", [PLAYER] = "Player" }

	rig.handshake()

	local entries: { any } = {}
	for slot: number in kinds do
		table.insert(entries, { slot = slot, generation = GENERATION, rig = "A" })
	end
	rig.slots(entries)

	for tick: number = TICK, TICK + FRAMES do
		local reveals: { any } = {}
		local records: { any } = {}

		for slot: number, kind: string in kinds do
			if tick == TICK then
				table.insert(reveals, { slot = slot, generation = GENERATION, kind = kind })
			end
			table.insert(records, { slot = slot, generation = GENERATION, position = AT, pitch = 0.5, word = word })
		end

		rig.relay({ tick = tick, reveals = reveals, records = records })
		rig.frames(1)
	end
	rig.frames(FRAMES)

	for _, slot: number in { SLEEPER, BODY } do
		if postures[slot] ~= "Downed" or pitches[slot] ~= 0 then
			return false, `The {kinds[slot]} was drawn {postures[slot]} with a pitch of {pitches[slot]}, not lying`
		end
	end

	if postures[PLAYER] ~= "Stand" then
		return false, `The player was drawn {postures[PLAYER]}, not standing`
	elseif #handle._world.bodies ~= 1 or handle._world.bodies[1] ~= handle._states[PLAYER] then
		return false, `{#handle._world.bodies} bodies were handed to the prediction, not the player's alone`
	end

	-- The player falls asleep in view: a fresh reveal of the sleeper kind lays the same rig down
	local checkouts: number = #rig.pool.of("checkout")
	local tick: number = TICK + FRAMES + 1
	rig.relay({
		tick = tick,
		reveals = { { slot = PLAYER, generation = GENERATION, kind = "Sleeper" } },
		records = { { slot = PLAYER, generation = GENERATION, position = AT, word = word } },
	})
	rig.frames(FRAMES)

	local asleep: any = nil
	for _, slot: any in spawned do
		if slot.id == PLAYER then
			asleep = slot
		end
	end

	if #rig.pool.of("checkout") ~= checkouts or postures[PLAYER] ~= "Downed" then
		return false, "The player who fell asleep wasn't laid down in the same rig"
	elseif #spawned ~= 3 or asleep == nil or asleep.kind ~= "Sleeper" then
		return false, "The player's Slot didn't change its kind to a sleeper in place"
	elseif #handle._world.bodies ~= 0 then
		return false, "A sleeper was handed to the owner's prediction to block against"
	end

	return true, nil
end
