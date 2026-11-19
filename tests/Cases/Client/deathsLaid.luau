--[[
    A death farther from the eye than bodies.radius, or reached more than
    bodies.late after the dying life's newest record, lays its rig down as
    the body's, drawn lying at once where it was and then at the body's
    records, while a near and timely one ragdolls. A body its reveal drew
    before its death gives its rig back, so no rig is left out unposed
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local GENERATION: number = 1
local FAR: number = 3 -- Dies past bodies.radius
local FAR_BODY: number = 20
local LATE: number = 4 -- Dies near, but its death comes past bodies.late
local LATE_BODY: number = 21
local NEAR: number = 5 -- Dies near and in time, so it ragdolls
local NEAR_BODY: number = 23
local DYING: number = 6 -- Its body is revealed before its death arrives
local EARLY_BODY: number = 22
local TICK: number = 50
local FRAMES: number = 6
local LATE_FRAMES: number = 140 -- Seven seconds at the simulation rate, past Frontier Zero's 6 s
local FAR_AT: vector = vector.create(1000, 0, 0) -- Past Frontier Zero's 250-stud radius from the eye at the origin
local NEAR_AT: vector = vector.create(2, 0, 0)

type Pose = { slot: number, posture: string, position: vector, pitch: number }

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs

	-- The pool's stand-in has no lie, so one is added that re-keys the rig as its ragdoll does and writes it down
	local lies: { { slot: number, body: number } } = {}
	local ragdoll: any = rigs.ragdoll
	rigs.lie = function (self: any, slot: number, body: number)
		table.insert(lies, { slot = slot, body = body })
		ragdoll(self, slot, body, nil)
	end

	-- Every pose with the posture it was drawn in
	local poses: { Pose } = {}
	local pose: any = rigs.pose
	rigs.pose = function (self: any, slot: number, state: any, distance: number, pitch: number)
		table.insert(poses, { slot = slot, posture = state.posture, position = state.position, pitch = pitch })
		pose(self, slot, state, distance, pitch)
	end

	local spawned: { { slot: any, rig: any } } = {}
	local despawned: { any } = {}
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
	end)
	handle:onDespawned(function (slot: any)
		table.insert(despawned, slot)
	end)

	local tick: number = TICK
	local function reveal(slot: number, kind: string, at: vector)
		rig.relay({
			tick = tick,
			reveals = { { slot = slot, generation = GENERATION, kind = kind } },
			records = { { slot = slot, generation = GENERATION, position = at } },
		})
		tick += 1
	end

	-- The last pose of a slot, nil for none
	local function lastPose(slot: number): Pose?
		for index: number = #poses, 1, -1 do
			if poses[index].slot == slot then
				return poses[index]
			end
		end

		return nil
	end

	rig.handshake()
	rig.slots({
		{ slot = FAR, generation = GENERATION, rig = "A" },
		{ slot = LATE, generation = GENERATION, rig = "A" },
		{ slot = NEAR, generation = GENERATION, rig = "A" },
		{ slot = DYING, generation = GENERATION, rig = "A" },
	})

	-- 1) Past the radius, the rig lies down at once where it was drawn, then at the body's own records
	reveal(FAR, "Player", FAR_AT)
	rig.frames(FRAMES)
	local farRig: any = spawned[#spawned].rig

	table.clear(poses)
	rig.slots({ { slot = FAR_BODY, generation = GENERATION, rig = "A" } })
	rig.death(FAR, GENERATION, FAR_BODY, GENERATION, vector.zero)

	local laid: Pose? = lastPose(FAR_BODY)
	if #lies ~= 1 or lies[1].slot ~= FAR or lies[1].body ~= FAR_BODY then
		return false, `A death past the radius laid {#lies} rigs down, not slot {FAR}'s into slot {FAR_BODY}`
	elseif not laid or laid.posture ~= "Downed" or laid.position ~= FAR_AT or laid.pitch ~= 0 then
		return false, "The body laid down wasn't drawn lying at once where its rig was"
	elseif spawned[#spawned].slot.id ~= FAR_BODY or spawned[#spawned].slot.kind ~= "Body" then
		return false, "The body laid down was told as no Body's spawn"
	elseif spawned[#spawned].rig ~= farRig or spawned[#spawned].slot.withheld ~= false then
		return false, "The body laid down was told with another rig than the one that died, or as withheld"
	end

	local moved: vector = FAR_AT + vector.create(0, 0, 4)
	reveal(FAR_BODY, "Body", moved)
	rig.frames(FRAMES)

	laid = lastPose(FAR_BODY)
	if not laid or laid.posture ~= "Downed" or laid.position ~= moved then
		return false, "The body laid down wasn't drawn lying at its own record once it came"
	elseif #handle._world.bodies ~= 0 then
		return false, "A body was handed to the owner's prediction to block against"
	end

	rig.slots({ { slot = FAR_BODY, generation = GENERATION } })
	local released: { any } = pool.of("release")
	if #released ~= 1 or released[1].slot ~= FAR_BODY then
		return false, "Freeing the laid body's slot didn't put its rig away"
	end

	-- 2) Near, but reached later than bodies.late after the newest record, the rig lies down too
	reveal(LATE, "Player", NEAR_AT)
	rig.frames(LATE_FRAMES)
	rig.slots({ { slot = LATE_BODY, generation = GENERATION, rig = "A" } })
	rig.death(LATE, GENERATION, LATE_BODY, GENERATION, vector.zero)

	if #lies ~= 2 or lies[2].slot ~= LATE then
		return false, "A death reached past bodies.late wasn't laid down"
	end

	-- 3) Near and in time, it ragdolls
	reveal(NEAR, "Player", NEAR_AT)
	rig.frames(FRAMES)
	rig.slots({ { slot = NEAR_BODY, generation = GENERATION, rig = "A" } })
	rig.death(NEAR, GENERATION, NEAR_BODY, GENERATION, vector.zero)

	if #lies ~= 2 or #pool.of("ragdoll") ~= #lies + 1 then
		return false, "A near and timely death didn't ragdoll"
	end

	-- 4) The body's reveal before its death: its own rig goes back, and the dying rig becomes the body's
	reveal(DYING, "Player", NEAR_AT)
	rig.frames(FRAMES)
	local dyingRig: any = spawned[#spawned].rig

	rig.slots({ { slot = EARLY_BODY, generation = GENERATION, rig = "A" } })
	reveal(EARLY_BODY, "Body", NEAR_AT)
	rig.frames(FRAMES)
	local earlyRig: any = spawned[#spawned].rig
	if spawned[#spawned].slot.id ~= EARLY_BODY or earlyRig == dyingRig then
		return false, "The body's early reveal didn't draw a rig of its own"
	end

	rig.death(DYING, GENERATION, EARLY_BODY, GENERATION, vector.zero)
	table.clear(poses)
	rig.frames(FRAMES)

	local giveBack: any = pool.of("release")[2]
	if giveBack == nil or giveBack.slot ~= EARLY_BODY or giveBack.rig ~= earlyRig then
		return false, "The body's own rig wasn't put away when its death came"
	elseif spawned[#spawned].slot.id ~= EARLY_BODY or spawned[#spawned].rig ~= dyingRig then
		return false, "The dying rig didn't become the early body's"
	elseif handle._rigged[DYING] ~= nil or lastPose(DYING) ~= nil then
		return false, "A rig stayed out for the dying slot, where nothing poses it"
	end

	return true, nil
end
