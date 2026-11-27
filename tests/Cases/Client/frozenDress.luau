--[[
    A look and a held item that changed while a player was hidden go onto
    its frozen body's kept rig as its reveal arrives, with no checkout, and
    a reveal that changes neither dresses nothing
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 6 -- Frames, a relay tick each, that take the render time past a block, with the delay
local SHIRT: number = 4 -- The look and the held item the player is first shown in
local ITEM: number = 7
local NEW_SHIRT: number = 9 -- What each changed to while anti-ESP hid the player
local NEW_ITEM: number = 12
local AT: vector = vector.create(100, 5, 200)

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	local spawned: { any } = {}
	handle:onSpawned(function (_: any, model: any)
		table.insert(spawned, model)
	end)

	local now: number = TICK -- The relay tick the server writes its next block at

	-- Runs frames of a relay tick each, the server's tick moving on with them
	local function run(frames: number)
		rig.frames(frames)
		now += frames
	end

	-- A reveal's block, which always carries the character's look and held item with its record
	local function reveal(shirt: number, item: number)
		rig.relay({
			tick = now,
			reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
			looks = { { slot = OTHER, generation = GENERATION, outfit = { shirt = shirt }, held = { item = item } } },
			records = { { slot = OTHER, generation = GENERATION, position = AT, word = rig.word({}) } },
		})
	end

	-- A hide anti-ESP made, and the frames that take the render time past it
	local function hide()
		rig.relay({ tick = now, hides = { { slot = OTHER, generation = GENERATION, culled = true } } })
		run(SETTLE)
	end

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A" } })

	reveal(SHIRT, ITEM)
	run(SETTLE)

	local checkouts: { any } = pool.of("checkout")
	local holds: { any } = pool.of("hold")
	if #checkouts ~= 1 or checkouts[1].outfit.shirt ~= SHIRT or #holds ~= 1 or holds[1].held.item ~= ITEM then
		return false, "The revealed player's rig wasn't checked out in its look, holding its item"
	end

	-- 1) The frozen body stays dressed, with its item in its hands
	local kept: any = checkouts[1].rig
	hide()
	if #pool.of("freeze") ~= 1 or #pool.of("release") ~= 0 then
		return false, "The hide anti-ESP made left no frozen body"
	elseif #pool.of("dress") ~= 0 or #pool.of("hold") ~= 1 then
		return false, "The freeze dressed the rig again or changed what it holds"
	end

	-- 2) Its reveal brings a new look and a new item, which go onto the kept rig as the reveal arrives
	reveal(NEW_SHIRT, NEW_ITEM)

	local dresses: { any } = pool.of("dress")
	holds = pool.of("hold")
	if #dresses ~= 1 or dresses[1].rig ~= kept or dresses[1].outfit.shirt ~= NEW_SHIRT then
		return false, `The reveal dressed {#dresses} rigs, not the kept rig in its new shirt {NEW_SHIRT}`
	elseif #holds ~= 2 or holds[2].rig ~= kept or holds[2].held.item ~= NEW_ITEM then
		return false, `The reveal gave the kept rig {#holds - 1} items, not its new item {NEW_ITEM}`
	elseif #pool.of("checkout") ~= 1 then
		return false, "The reveal checked a rig out, where the frozen body's is kept"
	end

	run(SETTLE)
	if #spawned ~= 2 or spawned[2] ~= kept then
		return false, "The reveal's first pose didn't tell the spawn of the kept rig"
	end

	-- 3) Hidden and shown again with nothing changed, the kept rig is dressed and handed nothing more
	hide()
	reveal(NEW_SHIRT, NEW_ITEM)
	run(SETTLE)
	if #pool.of("dress") ~= 1 or #pool.of("hold") ~= 2 or #pool.of("checkout") ~= 1 then
		return false, "A reveal that changed neither the look nor the held item dressed the kept rig again"
	elseif #spawned ~= 3 or spawned[3] ~= kept then
		return false, "The second reveal's first pose didn't tell the spawn of the kept rig"
	end

	return true, nil
end
