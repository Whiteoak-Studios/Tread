--[[
    A kept rig whose first pose after its reveal is past the draw distance,
    where the pool takes it out of Workspace, still has its spawn told
    once, with the frozen body's rig
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local STOOD: vector = vector.create(100, 5, 200) -- Where the player is first drawn, and so frozen
local SHOWN: vector = vector.create(1200, 5, 0) -- Where the server shows it again, past the desktop's draw distance

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	local spawned: { any } = {}
	local despawns: number = 0
	handle:onSpawned(function (_: any, model: any)
		table.insert(spawned, model)
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
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A" } })

	reveal(STOOD)
	run(SETTLE)
	rig.relay({ tick = now, hides = { { slot = OTHER, generation = GENERATION, culled = true } } })
	run(SETTLE)

	if #spawned ~= 1 or despawns ~= 1 or #pool.of("freeze") ~= 1 then
		return false, "The player's hide anti-ESP made left no frozen body"
	end

	-- The server shows the player again past the draw distance, so the first pose takes the kept rig out of Workspace
	local poses: number = #pool.of("pose")
	reveal(SHOWN)
	if #spawned ~= 1 then
		return false, "The kept rig's spawn was told when its reveal arrived"
	end

	run(SETTLE)

	local posed: { any } = pool.of("pose")
	local first: any = posed[poses + 1]
	if first == nil or first.position ~= SHOWN or first.distance <= pool.drawDistance then
		return false, `The kept rig's first pose wasn't past the draw distance of {pool.drawDistance} studs`
	elseif #spawned ~= 2 or spawned[2] ~= spawned[1] then
		return false,
			`A first pose past the draw distance told {#spawned - 1} spawns of the kept rig, not one with that rig`
	elseif despawns ~= 1 or #pool.of("checkout") ~= 1 or #pool.of("release") ~= 0 then
		return false, "The kept rig's spawn past the draw distance came with a despawn, a checkout or a release"
	end

	return true, nil
end
