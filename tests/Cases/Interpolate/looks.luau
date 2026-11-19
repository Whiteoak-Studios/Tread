--[[
    A look entry's parts are told only when they change: a repeat of the
    same bytes is not, a held part of length 0 holds nothing, a part from a
    block older than its last is stale, and the viewer's own slot's count
--]]

--!strict
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 40
local OWN: number = 41 -- The viewer's own slot, never revealed to it
local GENERATION: number = 1

return function (): (boolean, string | nil)
	local viewer = Viewer.new()

	viewer.announce(SLOT, GENERATION, "A")
	viewer.announce(OWN, GENERATION, "A")

	local function look(tick: number, entry: { [string]: any })
		entry.slot = entry.slot or SLOT
		entry.generation = GENERATION
		viewer.send({ tick = tick, looks = { entry } })
	end

	viewer.send({
		tick = 10,
		reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } },
		looks = { { slot = SLOT, generation = GENERATION, outfit = Game.high.slot, held = Game.high.held } },
		records = { { slot = SLOT, generation = GENERATION, position = vector.zero } },
	})

	-- The reveal's look repeated until acknowledged
	look(11, { outfit = Game.high.slot, held = Game.high.held })

	if #viewer.dresses ~= 1 or #viewer.holds ~= 1 then
		return false, `A look and its repeat were told {#viewer.dresses} and {#viewer.holds} times, not once each`
	end

	-- A new look alone
	look(12, { outfit = Game.low.slot })

	local differs: string? = Same(Game.low.slot, viewer.dresses[2] and viewer.dresses[2].outfit, "the new look")
	if #viewer.dresses ~= 2 or #viewer.holds ~= 1 then
		return false, "A change of look alone wasn't told as one look change"
	elseif differs then
		return false, differs
	end

	-- Nothing held
	look(13, { empty = true })
	if #viewer.holds ~= 2 or viewer.holds[2].held ~= nil then
		return false, "A held part of length 0 wasn't told as nothing held"
	end

	-- Held again
	look(14, { held = Game.low.held })
	differs = Same(Game.low.held, viewer.holds[3] and viewer.holds[3].held, "the new held item")
	if #viewer.holds ~= 3 then
		return false, "A held item after holding nothing wasn't told"
	elseif differs then
		return false, differs
	end

	-- A look from a block older than the one the last look came in, arriving late
	look(11, { outfit = Game.high.slot })
	if #viewer.dresses ~= 2 then
		return false, "A look entry from an older block than the last look's was told"
	end

	-- The viewer's own slot, dressed on its own screen though never revealed to it
	look(15, { slot = OWN, outfit = Game.high.slot })
	if #viewer.dresses ~= 3 or viewer.dresses[3].slot ~= OWN then
		return false, "A look change for the viewer's own slot wasn't told"
	end

	return true, nil
end
