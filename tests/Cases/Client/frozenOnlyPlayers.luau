--[[
    Only a drawn player's rig freezes. An NPC's, a sleeper's and a body's
    hide anti-ESP made, a player's no pose has placed or the pool refuses,
    and a player's while the client spectates each give the rig back
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local NPC: number = 3
local SLEEPER: number = 4
local BODY: number = 5
local UNDRAWN: number = 6 -- A player hidden before any pose draws it, whose rig the pool has no place for
local REFUSED: number = 8 -- A drawn player whose rig the pool refuses to freeze
local SEEN: number = 7 -- A player the spectated target is sent
local TARGET: number = 14
local GENERATION: number = 1
local TICK: number = 50
local RELAY: number = 20 -- Relay ticks a second, the example's
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local LONG: number = 1 -- Seconds of one frame that takes the render time past a reveal and the hide after it at once
local AT: vector = vector.create(30, 0, 40)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local Record: any = rig.globals.require(rig.tread.Codec.Record)

	-- The pool's stand-in has no outline or watch, which a spectating client calls, so each is added
	rigs.outline = function (_: any, _: number, _: boolean) end
	rigs.watch = function (_: any, _: number?) end

	local spawns: number = 0
	local despawned: { [number]: number } = {} -- How many despawns each slot was told
	handle:onSpawned(function (_: any, _: any)
		spawns += 1
	end)
	handle:onDespawned(function (slot: any)
		despawned[slot.id] = (despawned[slot.id] or 0) + 1
	end)

	local now: number = TICK -- The relay tick the server writes its next block at

	-- Runs frames of a relay tick each, the server's tick moving on with them
	local function run(frames: number)
		rig.frames(frames)
		now += frames
	end

	local function reveal(kinds: { [number]: string })
		local reveals: { any } = {}
		local records: { any } = {}
		for slot: number, kind: string in kinds do
			table.insert(reveals, { slot = slot, generation = GENERATION, kind = kind })
			table.insert(records, { slot = slot, generation = GENERATION, position = AT, word = rig.word({}) })
		end

		rig.relay({ tick = now, reveals = reveals, records = records })
	end

	-- A hide anti-ESP made of each slot
	local function hide(kinds: { [number]: string })
		local hides: { any } = {}
		for slot: number in kinds do
			table.insert(hides, { slot = slot, generation = GENERATION, culled = true })
		end

		rig.relay({ tick = now, hides = hides })
	end

	-- Whether a slot's rig went back to the pool once and its despawn was told once
	local function putAway(slot: number): boolean
		local releases: number = 0
		for _, call: any in pool.of("release") do
			if call.slot == slot then
				releases += 1
			end
		end

		return releases == 1 and despawned[slot] == 1
	end

	local entries: { any } = {}
	for _, slot: number in { NPC, SLEEPER, BODY, UNDRAWN, REFUSED, SEEN, TARGET } do
		table.insert(entries, { slot = slot, generation = GENERATION, rig = "A" })
	end

	rig.handshake()
	rig.slots(entries)

	-- 1) An NPC, a sleeper and a body, each drawn and then hidden by anti-ESP
	local others: { [number]: string } = { [NPC] = "Npc", [SLEEPER] = "Sleeper", [BODY] = "Body" }
	reveal(others)
	run(SETTLE)
	hide(others)
	run(SETTLE)

	for slot: number, kind: string in others do
		if not putAway(slot) then
			return false, `The {kind}'s hide anti-ESP made didn't give its rig back and tell its despawn once`
		end
	end

	if #pool.of("freeze") ~= 0 then
		return false, `{#pool.of("freeze")} rigs that were no player's were handed to the pool to freeze`
	end

	-- 2) A player shown and hidden with one frame passing both, so the hide ends a stretch no pose has drawn
	local poses: number = #pool.of("pose")
	reveal({ [UNDRAWN] = "Player" })
	now += 1
	hide({ [UNDRAWN] = "Player" })
	rig.frames(1, LONG)
	now += LONG * RELAY

	if #pool.of("pose") ~= poses then
		return false, "The frame that passed the reveal and its hide posed the rig, so no undrawn player is tested"
	elseif #pool.of("freeze") ~= 0 then
		return false, "The pool was asked to freeze a rig no pose had placed"
	elseif not putAway(UNDRAWN) then
		return false, "A player's rig no pose had drawn wasn't given back with its despawn told once"
	end

	-- 3) A drawn player whose rig the pool refuses, as the real pool refuses one out of Workspace, outlined or dying.
	-- The stand-in would freeze this rig, so its freeze answers false for the slot and counts the asking
	local refusals: number = 0
	local freeze: any = rigs.freeze
	rigs.freeze = function (self: any, slot: number): boolean
		if slot ~= REFUSED then
			return freeze(self, slot)
		end

		refusals += 1

		return false
	end

	reveal({ [REFUSED] = "Player" })
	run(SETTLE)
	hide({ [REFUSED] = "Player" })
	run(SETTLE)

	if refusals ~= 1 then
		return false, `The pool was asked {refusals} times to freeze the drawn player's rig, not once`
	elseif not putAway(REFUSED) then
		return false, "A player's rig the pool refused to freeze wasn't given back with its despawn told once"
	end

	-- 4) While the client spectates, a drawn player's hide anti-ESP made freezes nothing
	rig.send("Spectate", Record.id(TARGET, GENERATION), now)
	reveal({ [SEEN] = "Player" })
	run(SETTLE)
	hide({ [SEEN] = "Player" })
	run(SETTLE)

	if #pool.of("freeze") ~= 0 then
		return false, "A hide anti-ESP made froze a player's rig while the client spectated"
	elseif not putAway(SEEN) then
		return false, "A player hidden while the client spectated wasn't given back with its despawn told once"
	elseif spawns ~= 6 then
		return false, `{spawns} spawns were told, not one for each of the six characters drawn`
	end

	return true, nil
end
