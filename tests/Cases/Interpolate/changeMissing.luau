--[[
    A change naming a record this client never received drops that record
    alone: the block's whole records and the changes it could rebuild are
    drawn, and the block goes unacknowledged, so the server falls back to
    an older baseline, which the next block's change rebuilds against
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local LOST: number = 5 -- Its change names the record a lost block carried
local KEPT: number = 6 -- Its change names a record received
local WHOLE: number = 7 -- Sent whole
local GENERATION: number = 1
local FIRST: number = 10 -- The tick of the block both viewers get
local GONE: number = 11 -- The tick of the block lost on its way
local NEXT: number = 12 -- The block with the change that can't be rebuilt
local LATER: number = 13 -- The block whose change names the record before the lost one
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local AFTER: number = 10 -- Frames drawn past the last block
local START: vector = vector.create(-300, 20, 400)
local STRIDE: number = 0.5 -- Studs each slot moves a relay tick

return function (): (boolean, string | nil)
	-- The viewer sent changes, and one sent the same records whole, the record that can't be rebuilt left out
	local changed = Viewer.new()
	local whole = Viewer.new()

	for _, viewer in { changed, whole } do
		for _, slot: number in { LOST, KEPT, WHOLE } do
			viewer.announce(slot, GENERATION, "A")
		end
	end

	local function record(slot: number, tick: number): buffer
		local at: vector = START + vector.create(slot, 0, (tick - FIRST) * STRIDE)

		return Changes.record({ slot = slot, generation = GENERATION, position = at })
	end

	local function frames(count: number, when: string): string?
		for _ = 1, count do
			changed.Interpolate.frame(FRAME)
			whole.Interpolate.frame(FRAME)

			for _, slot: number in { LOST, KEPT, WHOLE } do
				local drawn: boolean, state: any = changed.pose(slot)
				local wholeDrawn: boolean, wholeState: any = whole.pose(slot)
				if drawn ~= wholeDrawn or (drawn and state.position ~= wholeState.position) then
					return `{when}, slot {slot} was drawn at {drawn and state.position}, not {wholeState.position}`
				end
			end
		end

		return nil
	end

	local reveals: { any } = {}
	for _, slot: number in { LOST, KEPT, WHOLE } do
		table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
	end

	local opening: buffer = Changes.block({
		sequence = 1,
		tick = FIRST,
		reveals = reveals,
		records = { record(LOST, FIRST), record(KEPT, FIRST), record(WHOLE, FIRST) },
	})
	changed.Interpolate.receive(opening)
	whole.Interpolate.receive(opening)

	local why: string? = frames(NEXT - FIRST, "Before the change that can't be rebuilt")
	if why then
		return false, why
	end

	-- 1) The block at GONE never came, so LOST's change against it drops while KEPT's and WHOLE's records go on
	changed.Interpolate.receive(Changes.block({
		sequence = 3,
		tick = NEXT,
		records = { record(WHOLE, NEXT) },
		changes = {
			Changes.change(record(LOST, NEXT), record(LOST, GONE), NEXT - GONE),
			Changes.change(record(KEPT, NEXT), record(KEPT, FIRST), NEXT - FIRST),
		},
	}))
	whole.Interpolate.receive(Changes.block({
		sequence = 3,
		tick = NEXT,
		records = { record(WHOLE, NEXT), record(KEPT, NEXT) },
	}))

	local acknowledged: number, mask: number = changed.Interpolate.received()
	if acknowledged ~= 1 or mask ~= 0 then
		return false, `The block with a change it couldn't rebuild moved the acknowledgment to {acknowledged}`
	end

	why = frames(LATER - NEXT, "After the change that can't be rebuilt")
	if why then
		return false, why
	end

	-- 2) The server, with no newer acknowledgment, names the record before the lost one, which rebuilds
	changed.Interpolate.receive(Changes.block({
		sequence = 4,
		tick = LATER,
		changes = { Changes.change(record(LOST, LATER), record(LOST, FIRST), LATER - FIRST) },
	}))
	whole.Interpolate.receive(Changes.block({ sequence = 4, tick = LATER, records = { record(LOST, LATER) } }))

	-- 4 is the newest, 3 left unacknowledged on bit 0 and 2 lost on bit 1, with 1 on bit 2
	acknowledged, mask = changed.Interpolate.received()
	if acknowledged ~= 4 or mask ~= 0b100 then
		return false, `The block rebuilt whole left the acknowledgment at {acknowledged} with {mask}, not 4 with 4`
	end

	why = frames(AFTER, "Past the last block")
	if why then
		return false, why
	end

	return true, nil
end
