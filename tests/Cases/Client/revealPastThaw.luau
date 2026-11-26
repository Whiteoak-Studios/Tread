--[[
    A frozen body's reveal carrying the player's past at the 100 ms floor
    thaws it on the first frame after the block arrives, moving the kept
    rig to where the slot is drawn and telling its spawn that frame, while
    the same reveal with no past waits for the render time to reach its tick
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local QUICK: number = 3 -- Revealed with its past
local SLOW: number = 4 -- Revealed with none
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local FRAMES: number = 4 -- Frames after the reveal, more than the render time takes to reach its tick
local AGES: { number } = { 3, 2, 1 } -- The past the floor's span gives, oldest first
local STOOD: vector = vector.create(100, 5, 200) -- Where each player is first drawn, and so frozen
local SHOWN: vector = vector.create(40, 5, -30) -- Where the server shows it again
local STEP: vector = vector.create(1, 0, 0) -- Studs a relay tick the revealed player walks toward SHOWN
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local Interpolate: any = rig.Interpolate

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

	-- How many of the pool's calls of a member, a spawn told among them, named a slot since they were last cleared
	local function seen(member: string, slot: number): number
		local count: number = 0
		for _, call: any in pool.calls do
			if call.member == member and call.slot == slot then
				count += 1
			end
		end

		return count
	end

	local quick: any = roblox.Instance.new("Player")
	local slow: any = roblox.Instance.new("Player")
	rig.handshake()
	rig.slots({
		{ slot = QUICK, generation = GENERATION, rig = "A", player = quick },
		{ slot = SLOW, generation = GENERATION, rig = "A", player = slow },
	})

	-- Both drawn, then hidden by anti-ESP, so each leaves a frozen body
	rig.relay({
		tick = now,
		reveals = {
			{ slot = QUICK, generation = GENERATION, kind = "Player" },
			{ slot = SLOW, generation = GENERATION, kind = "Player" },
		},
		records = {
			{ slot = QUICK, generation = GENERATION, position = STOOD },
			{ slot = SLOW, generation = GENERATION, position = STOOD },
		},
	})
	run(SETTLE)
	rig.relay({
		tick = now,
		hides = {
			{ slot = QUICK, generation = GENERATION, culled = true },
			{ slot = SLOW, generation = GENERATION, culled = true },
		},
	})
	run(SETTLE)

	if #spawned ~= 2 or #despawned ~= 2 or #pool.of("freeze") ~= 2 or #pool.of("release") ~= 0 then
		return false, "The two players' hides anti-ESP made left no two frozen bodies"
	end

	local kept: any = nil
	for _, told: { slot: any, rig: any } in spawned do
		if told.slot.id == QUICK then
			kept = told.rig
		end
	end

	-- 1) The reveals arrive, QUICK's with the records that walked it to SHOWN, and nothing changes on screen yet
	local revealed: number = now
	local past: { any } = {}
	for _, age: number in AGES do
		table.insert(past, { age = age, record = { position = SHOWN - STEP * age } })
	end

	rig.relay({
		tick = revealed,
		reveals = {
			{ slot = QUICK, generation = GENERATION, kind = "Player", past = past },
			{ slot = SLOW, generation = GENERATION, kind = "Player" },
		},
		records = {
			{ slot = QUICK, generation = GENERATION, position = SHOWN },
			{ slot = SLOW, generation = GENERATION, position = SHOWN },
		},
	})

	if #spawned ~= 2 or #pool.of("checkout") ~= 2 then
		return false, "A frozen body's reveal told a spawn or checked a rig out as it arrived"
	end

	-- 2) The first frame after it poses QUICK's kept rig where the slot is drawn, and tells its spawn after the frame's
	-- end has moved it there
	table.clear(pool.calls)
	run(1)

	local time: number = Interpolate.renderTime()
	local state: any = rig.State.new()
	local drawn: boolean = Interpolate.pose(QUICK, state)
	local poses: { any } = pool.of("pose")
	local calls: { any } = pool.calls
	local shown: { slot: any, rig: any }? = spawned[3]

	if not (time >= revealed - AGES[1] and time < revealed) then
		return false, `The first frame after the reveal put the render time at {time}, outside the past it carries`
	elseif not drawn or #poses ~= 1 or poses[1].slot ~= QUICK or poses[1].rig ~= kept then
		return false, `The first frame after the reveal posed {#poses} rigs, not QUICK's kept rig alone`
	elseif poses[1].position ~= state.position then
		return false, `QUICK's kept rig was posed at {poses[1].position}, not where its slot is drawn, {state.position}`
	elseif vector.magnitude(state.position - (SHOWN - STEP * (revealed - time))) > CLOSE then
		return false, `QUICK was drawn at {state.position}, off the path its past walked`
	elseif shown == nil or shown.slot.id ~= QUICK or shown.rig ~= kept or #spawned ~= 3 then
		return false, "The first frame after the reveal told no spawn of QUICK with its kept rig, or told another"
	elseif calls[#calls].member ~= "spawned" or calls[#calls - 1].member ~= "frame" then
		return false, "QUICK's spawn was told before the pool's frame end had moved its rig"
	elseif #despawned ~= 2 or #pool.of("checkout") ~= 0 then
		return false, "QUICK's thaw came with a despawn or a checkout"
	end

	-- 3) SLOW, with no past, stays frozen until the frame whose render time reaches its reveal's tick, as before
	local reached: boolean = false
	for frame: number = 1, FRAMES do
		table.clear(pool.calls)
		run(1)

		reached = Interpolate.renderTime() >= revealed
		local posed: boolean = seen("pose", SLOW) > 0
		if posed ~= reached or seen("spawned", SLOW) ~= (reached and 1 or 0) then
			local at: string = `render time {Interpolate.renderTime()}`
			return false, `Frame {frame + 1} after the reveal posed SLOW {posed} and told its spawn at {at}`
		elseif reached then
			break
		end
	end

	if not reached then
		return false, `{FRAMES + 1} frames after the reveal the render time was {Interpolate.renderTime()}, short of it`
	end

	return true, nil
end
