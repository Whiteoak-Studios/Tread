--[[
    A spectate's start or end restarts the view at its tick: each slot whose
    newest record is older closes, told as a hide, one with a newer record
    stays, a block older than the tick is dropped, and the acknowledgment
    starts again from the next block, acknowledging none until it comes
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local KEPT: number = 5 -- Its newest record is the restart's tick, so it stays
local CLOSED: number = 6 -- Its newest record is older, so it closes
local LATE: number = 7 -- Revealed only on a straggler of the old view
local GENERATION: number = 1
local FIRST: number = 10
local START: number = 12 -- The relay tick the new view starts at
-- The target's own sequences, which the moderator acknowledges from now on: just short of the wrap, so they read as
-- older than an acknowledgment of none unless the acknowledgment starts again
local TARGET_SEQUENCE: number = 65530

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	for _, slot: number in { KEPT, CLOSED, LATE } do
		viewer.announce(slot, GENERATION, "A")
	end

	-- The moderator's own view, its sequences 1 to 3
	for tick: number = FIRST, START do
		local records: { any } = { { slot = KEPT, generation = GENERATION, position = vector.create(tick, 0, 0) } }
		local reveals: { any }? = nil
		if tick == FIRST then
			reveals = {
				{ slot = KEPT, generation = GENERATION, kind = "Player" },
				{ slot = CLOSED, generation = GENERATION, kind = "Player" },
			}
			table.insert(records, { slot = CLOSED, generation = GENERATION, position = vector.zero })
		end

		viewer.send({ tick = tick, reveals = reveals, records = records })
	end

	local acknowledged: number, mask: number = Interpolate.received()
	if acknowledged ~= 3 or mask ~= 3 then
		return false, `Before the restart the viewer acknowledged {acknowledged} with mask {mask}, not 3 with 3`
	end

	Interpolate.restart(START)

	if #viewer.hides ~= 1 or viewer.hides[1] ~= CLOSED then
		return false, `The restart closed {#viewer.hides} slots, not slot {CLOSED} alone`
	end

	acknowledged, mask = Interpolate.received()
	if acknowledged ~= 0 or mask ~= 0 then
		return false, `After the restart the viewer acknowledged {acknowledged} with mask {mask}, before any block`
	end

	-- A straggler of the old view, older than the new view's first tick, is dropped whole
	viewer.send({
		tick = START - 1,
		sequence = 4,
		reveals = { { slot = LATE, generation = GENERATION, kind = "Player" } },
		records = { { slot = LATE, generation = GENERATION, position = vector.zero } },
	})

	acknowledged = Interpolate.received()
	if acknowledged ~= 0 or #viewer.reveals ~= 2 then
		return false, "A block from before the restart's tick was acknowledged or applied"
	end

	-- The target's blocks, in its own sequences, start the acknowledgment afresh
	viewer.send({ tick = START, sequence = TARGET_SEQUENCE })
	acknowledged, mask = Interpolate.received()
	if acknowledged ~= TARGET_SEQUENCE or mask ~= 0 then
		return false,
			`The first block after the restart left {acknowledged} with mask {mask}, not {TARGET_SEQUENCE} with 0`
	end

	viewer.send({ tick = START + 1, sequence = TARGET_SEQUENCE + 2 })
	acknowledged, mask = Interpolate.received()
	if acknowledged ~= TARGET_SEQUENCE + 2 or mask ~= 2 then
		return false, `A later block left {acknowledged} with mask {mask}, not {TARGET_SEQUENCE + 2} with 2`
	end

	-- The kept slot still draws, and the closed one does once the new view reveals it
	viewer.send({
		tick = START + 2,
		sequence = TARGET_SEQUENCE + 3,
		reveals = { { slot = CLOSED, generation = GENERATION, kind = "Player" } },
		records = { { slot = CLOSED, generation = GENERATION, position = vector.zero } },
	})
	Interpolate.frame(1)

	if not viewer.pose(KEPT) then
		return false, "The slot with a record at the restart's tick stopped drawing"
	elseif #viewer.reveals ~= 3 or viewer.reveals[3].slot ~= CLOSED or not viewer.pose(CLOSED) then
		return false, "The closed slot wasn't drawn again by the new view's reveal"
	end

	return true, nil
end
