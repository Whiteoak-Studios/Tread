--[[
    A record, hide or look entry naming an older generation than the slot
    table's is ignored, generations count newer across their 4-bit wrap,
    and freeing a slot or giving it a new life ends the life drawn now
--]]

--!strict
local Game = require("../../Fixtures/Codec/Game")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 30
local WRAPPED: number = 31 -- At generation 15, then 0
local FREED: number = 32
local RENEWED: number = 33
local TOLERANCE: number = 1e-6

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	local function count(list: { any }, slot: number): number
		local found: number = 0
		for _, entry: any in list do
			if entry == slot or (type(entry) == "table" and entry.slot == slot) then
				found += 1
			end
		end

		return found
	end

	viewer.announce(SLOT, 3, "A")
	viewer.announce(WRAPPED, 15, "A")
	viewer.announce(FREED, 4, "A")
	viewer.announce(RENEWED, 1, "A")

	viewer.send({
		tick = 10,
		reveals = {
			{ slot = SLOT, generation = 3, kind = "Player" },
			{ slot = WRAPPED, generation = 0, kind = "Player" },
			{ slot = FREED, generation = 4, kind = "Player" },
			{ slot = RENEWED, generation = 1, kind = "Player" },
		},
		records = {
			{ slot = SLOT, generation = 3, position = vector.create(0, 0, 0) },
			{ slot = FREED, generation = 4, position = vector.zero },
			{ slot = RENEWED, generation = 1, position = vector.zero },
		},
	})

	viewer.send({ tick = 11, records = { { slot = SLOT, generation = 3, position = vector.create(1, 0, 0) } } })

	-- Generation 2's record, hide and look, all a life too old
	viewer.send({
		tick = 12,
		hides = { { slot = SLOT, generation = 2 } },
		looks = { { slot = SLOT, generation = 2, outfit = Game.low.slot } },
		records = { { slot = SLOT, generation = 2, position = vector.create(50, 0, 0) } },
	})

	viewer.send({ tick = 13, records = { { slot = SLOT, generation = 3, position = vector.create(3, 0, 0) } } })
	viewer.send({ tick = 14 })
	viewer.send({ tick = 15 })

	-- 3 ticks behind 15, and half a tick on, between the records at 11 and 13
	Interpolate.frame(0)
	Interpolate.frame(0.025)

	local drawn: boolean, state: any = viewer.pose(SLOT)
	if not drawn or math.abs(state.position.x - 2.5) > TOLERANCE then
		return false, `The slot drew at {state.position}, where an older generation's record moved it`
	elseif #viewer.dresses ~= 0 then
		return false, "An older generation's look entry was told"
	end

	Interpolate.frame(0.5)
	if count(viewer.hides, SLOT) ~= 0 then
		return false, "An older generation's hide closed the slot's stretch"
	end

	-- 0 is newer than 15 across the wrap, so its reveal waited for the entry
	if count(viewer.reveals, WRAPPED) ~= 0 then
		return false, "A reveal of generation 0 applied while the table held the slot at 15"
	end

	viewer.announce(WRAPPED, 0, "A")
	if count(viewer.reveals, WRAPPED) ~= 1 then
		return false, "Generation 0's held reveal wasn't told once the table moved the slot from 15 to 0"
	end

	-- Freed, the life drawn now ends at once, and later entries for it are ignored
	viewer.announce(FREED, 4, nil)
	if count(viewer.hides, FREED) ~= 1 then
		return false, "Freeing a drawn slot didn't end its stretch"
	end

	viewer.send({
		tick = 16,
		reveals = { { slot = FREED, generation = 4, kind = "Player" } },
		records = { { slot = FREED, generation = 4, position = vector.zero } },
	})

	if count(viewer.reveals, FREED) ~= 1 or viewer.pose(FREED) then
		return false, "A freed slot's generation was revealed or drawn again"
	end

	-- A new life ends the old one at once
	viewer.announce(RENEWED, 2, "A")
	if count(viewer.hides, RENEWED) ~= 1 then
		return false, "A drawn slot's new generation didn't end its old life's stretch"
	end

	return true, nil
end
