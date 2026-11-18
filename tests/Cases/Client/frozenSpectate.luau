--[[
    A frozen body revealed by a spectate's new view before the Spectate
    message keeps its rig through the spectate's start, and is outlined
    only from the frame after its first pose has told its spawn
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3 -- The player whose frozen body the new view reveals
local TARGET: number = 14 -- The spectate's target
local GENERATION: number = 1
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local STOOD: vector = vector.create(100, 5, 200) -- Where the player is first drawn, and so frozen
local SHOWN: vector = vector.create(40, 5, -30) -- Where the new view shows it

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local Record: any = rig.globals.require(rig.tread.Codec.Record)
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	-- The pool's stand-in has no outline or watch and its frame end writes nothing down, so the case writes each
	-- outline and each frame end down beside the pool's calls, and each spawn told beside them
	rigs.outline = function (_: any, slot: number, outlined: boolean)
		table.insert(pool.calls, { member = "outline", slot = slot, outlined = outlined })
	end
	rigs.watch = function (_: any, _: number?) end
	rigs.frame = function (_: any)
		table.insert(pool.calls, { member = "frame" })
	end

	local spawned: { { slot: any, rig: any } } = {}
	local despawns: number = 0
	handle:onSpawned(function (slot: any, model: any)
		table.insert(spawned, { slot = slot, rig = model })
		table.insert(pool.calls, { member = "spawned", slot = slot.id })
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

	local function reveal(at: vector)
		rig.relay({
			tick = now,
			reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
			records = { { slot = OTHER, generation = GENERATION, position = at, word = rig.word({}) } },
		})
	end

	rig.handshake()
	rig.slots({
		{ slot = OTHER, generation = GENERATION, rig = "A", player = other },
		{ slot = TARGET, generation = GENERATION, rig = "A" },
	})

	-- The moderator's own view draws the player, and anti-ESP hides it, so it leaves a frozen body
	reveal(STOOD)
	run(SETTLE)
	rig.relay({ tick = now, hides = { { slot = OTHER, generation = GENERATION, culled = true } } })
	run(SETTLE)

	if #spawned ~= 1 or despawns ~= 1 or #pool.of("freeze") ~= 1 or #pool.of("release") ~= 0 then
		return false, "The player's hide anti-ESP made left no frozen body"
	end

	-- 1) The new view's first block, at the view's tick, reveals the player and arrives before the Spectate message
	local kept: any = spawned[1].rig
	reveal(SHOWN)
	rig.send("Spectate", Record.id(TARGET, GENERATION), now)

	if #pool.of("release") ~= 0 or #pool.of("checkout") ~= 1 then
		return false, "The spectate's start gave back the kept rig its new view had revealed, or checked one out"
	elseif #spawned ~= 1 or despawns ~= 1 then
		return false, "The spectate's start told a spawn or a despawn of the kept rig"
	end

	-- 2) Until its first pose the rig stands frozen where its hide left it, so no outline is asked for it. The pool's
	-- calls are cleared before each frame, so each count is of that frame's calls
	local frames: number = 0
	while #spawned == 1 and frames < SETTLE do
		table.clear(pool.calls)
		run(1)
		frames += 1

		if #pool.of("outline") ~= 0 then
			return false, `Frame {frames} after the spectate's start outlined the kept rig before its spawn was told`
		end
	end

	local calls: { any } = pool.calls
	local poses: { any } = pool.of("pose")
	local shown: any = spawned[2]
	if shown == nil then
		return false, `{SETTLE} frames after the spectate's start the kept rig's spawn was never told`
	elseif shown.rig ~= kept or shown.slot.id ~= OTHER or shown.slot.player ~= other then
		return false, "The spawn told while spectating handed another rig than the frozen body's"
	elseif #poses ~= 1 or poses[1].rig ~= kept or poses[1].position ~= SHOWN then
		return false, "The frame that told the kept rig's spawn didn't pose it once where the new view shows it"
	elseif calls[#calls].member ~= "spawned" or calls[#calls - 1].member ~= "frame" then
		return false, "The kept rig's spawn was told before the pool's frame end had moved the rig"
	end

	-- 3) The frame after its spawn outlines it, as every other player in the view, and tells nothing again
	table.clear(pool.calls)
	run(1)

	local outlines: { any } = pool.of("outline")
	if #outlines ~= 1 or outlines[1].slot ~= OTHER or outlines[1].outlined ~= true then
		return false, `The frame after the kept rig's spawn asked for {#outlines} outlines, not slot {OTHER}'s`
	elseif #spawned ~= 2 or despawns ~= 1 or #pool.of("release") ~= 0 then
		return false, "The kept rig's spawn was told again, or the rig was given back"
	end

	return true, nil
end
