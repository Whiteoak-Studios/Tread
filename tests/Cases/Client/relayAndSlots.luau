--[[
    The slot table and relay blocks reach the remote interpolation, which
    draws a revealed player's rig with its look at its record, and the
    OwnerState reaches prediction, whose Moves acknowledge the relay and
    report the interpolation delay
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local FRAMES: number = 10
local SHIRT: number = 4
local MILLISECONDS: number = 1000

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	local spawned: { { slot: any, rig: any } } = {}
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
	end)

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })

	local at: vector = vector.create(100, 5, 200)
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		looks = { { slot = OTHER, generation = GENERATION, outfit = { shirt = SHIRT } } },
		records = { { slot = OTHER, generation = GENERATION, position = at, word = rig.word({}) } },
	})

	local checkouts: { any } = pool.of("checkout")
	if #spawned ~= 1 or #checkouts ~= 1 then
		return false, `A reveal drew {#spawned} rigs from {#checkouts} checkouts, not 1 from 1`
	end

	local slot: any = spawned[1].slot
	if slot.id ~= OTHER or slot.kind ~= "Player" or slot.player ~= other then
		return false, `The spawn named slot {slot.id}, a {slot.kind} of {slot.player}, not slot {OTHER}'s player`
	elseif spawned[1].rig ~= checkouts[1].rig or checkouts[1].slot ~= OTHER then
		return false, "The spawn handed another rig than the one checked out for its slot"
	elseif checkouts[1].outfit.shirt ~= SHIRT then
		return false, `The rig was checked out wearing shirt {checkouts[1].outfit.shirt}, not the look's {SHIRT}`
	end

	rig.frames(FRAMES)

	local poses: { any } = pool.of("pose")
	local last: any = poses[#poses]
	if last == nil or last.slot ~= OTHER then
		return false, `{FRAMES} frames posed {#poses} rigs, and not slot {OTHER}'s last`
	elseif last.position ~= at then
		return false, `Slot {OTHER} was posed at {last.position}, not its record's {at}`
	elseif math.abs(last.distance - vector.magnitude(at)) > 1e-9 then
		return false,
			`Slot {OTHER} was posed {last.distance} studs from an eye at the origin, not {vector.magnitude(at)}`
	end

	-- The drawn player is a body the owner's prediction blocks against
	local bodies: { any } = handle._world.bodies
	if #bodies ~= 1 or bodies[1].position ~= at then
		return false, `The owner's world held {#bodies} bodies, not the drawn player at {at}`
	end

	local renderTime: number = handle:getRenderTime()
	if renderTime ~= rig.Interpolate.renderTime() or renderTime < TICK then
		return false, `The render time read {renderTime}, not the interpolation's past the record's tick {TICK}`
	end

	-- The owner's own body, then a frame's Move
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	if handle:getState() == nil then
		return false, "An OwnerState of our slot started no body"
	end

	rig.frames(1)
	rig.step()

	local move: any = rig.moves[#rig.moves]
	local delay: number = math.round(rig.Interpolate.delay() * MILLISECONDS)
	if move == nil then
		return false, "The owner's first frame sent no Move"
	elseif move.acknowledged ~= rig.sequence then
		return false, `The Move acknowledged relay sequence {move.acknowledged}, not the newest, {rig.sequence}`
	elseif move.delay ~= delay then
		return false, `The Move reported a delay of {move.delay} ms, not the interpolation's {delay}`
	elseif move.count < 1 then
		return false, "The owner's first Move carried no command"
	end

	return true, nil
end
