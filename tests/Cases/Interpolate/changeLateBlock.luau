--[[
    A block arriving 32 relay ticks or more behind the newest files none of
    its records as baselines, so it never writes over the newer record the
    store keeps at the same place, which the next change rebuilds against
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 5
local GENERATION: number = 1
local FIRST: number = 100
local NEWER: number = 140 -- The newest block before the late one
local LATE: number = NEWER - 32 -- Kept, it would land on NEWER's place in the store
local LAST: number = NEWER + 1 -- Its change names NEWER's record
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local AFTER: number = 10 -- Frames drawn past the last block
local START: vector = vector.create(50, 0, 50)
local STRIDE: number = 0.25 -- Studs it moves a relay tick

local function record(tick: number): buffer
	local at: vector = START + vector.create((tick - FIRST) * STRIDE, 0, 0)

	return Changes.record({ slot = SLOT, generation = GENERATION, position = at })
end

return function (): (boolean, string | nil)
	-- The viewer sent the change, and one sent the record whole
	local changed = Viewer.new()
	local whole = Viewer.new()

	-- Each block's sequence in the order the server sent them, the late one second
	local blocks: { { sequence: number, tick: number } } = {
		{ sequence = 1, tick = FIRST },
		{ sequence = 3, tick = NEWER },
		{ sequence = 2, tick = LATE },
	}

	for _, viewer in { changed, whole } do
		viewer.announce(SLOT, GENERATION, "A")

		for index: number, block in blocks do
			local reveals: { any }? = nil
			if index == 1 then
				reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } }
			end

			viewer.Interpolate.receive(Changes.block({
				sequence = block.sequence,
				tick = block.tick,
				reveals = reveals,
				records = { record(block.tick) },
			}))
		end
	end

	changed.Interpolate.receive(Changes.block({
		sequence = 4,
		tick = LAST,
		changes = { Changes.change(record(LAST), record(NEWER), LAST - NEWER) },
	}))
	whole.Interpolate.receive(Changes.block({ sequence = 4, tick = LAST, records = { record(LAST) } }))

	-- 1) Every block acknowledged, the late one on its bit, so the change found NEWER's record where it was kept
	local acknowledged: number, mask: number = changed.Interpolate.received()
	if acknowledged ~= 4 or mask ~= 0b111 then
		return false,
			`The change after the late block left the acknowledgment at {acknowledged} with {mask}, not 4 with 7`
	end

	-- 2) Its record drawn as the one sent whole
	for frame: number = 1, AFTER do
		changed.Interpolate.frame(FRAME)
		whole.Interpolate.frame(FRAME)

		local drawn: boolean, state: any = changed.pose(SLOT)
		local wholeDrawn: boolean, wholeState: any = whole.pose(SLOT)
		if drawn ~= wholeDrawn or (drawn and state.position ~= wholeState.position) then
			return false, `On frame {frame} the slot was drawn at {drawn and state.position}, not {wholeState.position}`
		end
	end

	return true, nil
end
