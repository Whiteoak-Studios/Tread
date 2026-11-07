--[[
    A reveal, look entry or record for a slot the slot table hasn't
    announced, or has announced at an older generation, waits for its
    entry; a hide drops the reveal it follows, and a newer generation's
    entries replace an older one's
--]]

--!strict
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local UNANNOUNCED: number = 20 -- Revealed with its look and a record before the table names it
local OLDER: number = 21 -- Announced at generation 1, revealed at 2
local HIDDEN: number = 22 -- Revealed and hidden before the table names it
local REPLACED: number = 23 -- Revealed at generation 4, then at 5
local AT: vector = vector.create(5, 0, 5)

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	local function count(slot: number): number
		local found: number = 0
		for _, told: { [string]: any } in viewer.reveals do
			if told.slot == slot then
				found += 1
			end
		end

		return found
	end

	viewer.announce(OLDER, 1, "A")

	viewer.send({
		tick = 10,
		reveals = {
			{ slot = UNANNOUNCED, generation = 2, kind = "Npc" },
			{ slot = OLDER, generation = 2, kind = "Player" },
			{ slot = HIDDEN, generation = 3, kind = "Player" },
			{ slot = REPLACED, generation = 4, kind = "Player" },
		},
		looks = { { slot = UNANNOUNCED, generation = 2, outfit = Game.high.slot, held = Game.high.held } },
		records = { { slot = UNANNOUNCED, generation = 2, position = AT } },
	})

	viewer.send({
		tick = 11,
		hides = { { slot = HIDDEN, generation = 3 } },
		reveals = { { slot = REPLACED, generation = 5, kind = "Sleeper" } },
	})

	viewer.send({ tick = 12 })
	viewer.send({ tick = 13 })
	Interpolate.frame(0)

	if #viewer.reveals ~= 0 or #viewer.dresses ~= 0 or #viewer.holds ~= 0 then
		return false, "Entries for generations the slot table hadn't announced were told before their entries came"
	elseif viewer.pose(UNANNOUNCED) then
		return false, "A held record drew before the slot table announced its slot"
	end

	-- Its entry lets go of the reveal, the look and the record together
	viewer.announce(UNANNOUNCED, 2, "A")

	local told: { [string]: any }? = viewer.reveals[1]
	if not told or told.slot ~= UNANNOUNCED or told.kind ~= "Npc" then
		return false, "The held reveal wasn't told once the slot table announced its slot"
	end

	local differs: string? = Same(Game.high.slot, told.outfit, "the held look")
		or Same(Game.high.held, told.held, "the held item")
	if differs then
		return false, differs
	end

	if #viewer.dresses ~= 1 or #viewer.holds ~= 1 then
		return false, "The held look entry wasn't told once with its reveal"
	end

	local drawn: boolean, state: any = viewer.pose(UNANNOUNCED)
	if not drawn or state.position ~= AT then
		return false, `The held record drew {drawn} at {state.position}, not at {AT}`
	end

	viewer.announce(OLDER, 2, "A")
	if count(OLDER) ~= 1 then
		return false, "A reveal of a generation newer than the announced one wasn't held for its entry"
	end

	viewer.announce(HIDDEN, 3, "A")
	if count(HIDDEN) ~= 0 then
		return false, "A held reveal was told though a hide after it came before the slot's entry"
	end

	-- Generation 5 replaced 4 in the hold, so 4's entry lets go of nothing and 5's tells its reveal
	viewer.announce(REPLACED, 4, "A")
	if count(REPLACED) ~= 0 then
		return false, "The slot table's older generation let go of a reveal of the newer one"
	end

	viewer.announce(REPLACED, 5, "A")
	if count(REPLACED) ~= 1 or viewer.reveals[#viewer.reveals].kind ~= "Sleeper" then
		return false, "The newer generation's held reveal wasn't told when its entry came"
	end

	return true, nil
end
