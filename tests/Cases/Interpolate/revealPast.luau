--[[
    A player's reveal carrying its past draws on the first frame after it
    arrives, as a ring of those records draws at the render time; one with
    none waits for the render time to reach its tick, a held reveal's past
    is dropped, and no past record is a change's baseline
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local PAST: number = 5 -- Revealed with its past
local BARE: number = 6 -- Revealed with none
local HELD: number = 7 -- Revealed with its past before the slot table names it
local GENERATION: number = 1
local DELAY: number = 0.10 -- Seconds, the interpolation delay's floor
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local FIRST: number = 10 -- The first block's tick, which starts the render clock
local REVEAL: number = 20 -- The reveals' block
local NEXT: number = 21 -- A change against a past record's tick
local AFTER: number = 22 -- A change against the reveal's own record
local AGES: { number } = { 3, 2, 1 } -- The past the floor's span gives, oldest first
local FRAMES: number = 4 -- Frames past the reveal, more than the render time takes to reach its tick

-- Where a slot stands at a tick, each on its own line
local function at(slot: number, tick: number): vector
	return vector.create(tick, 0, slot)
end

local function record(slot: number, tick: number): { [string]: any }
	return { slot = slot, generation = GENERATION, position = at(slot, tick) }
end

-- A slot's past behind its reveal at REVEAL, a record for each age
local function past(slot: number): { any }
	local entries: { any } = {}
	for _, age: number in AGES do
		table.insert(entries, { age = age, record = record(slot, REVEAL - age) })
	end

	return entries
end

return function (): (boolean, string | nil)
	local viewer = Viewer.new(nil, DELAY)
	local Interpolate: any = viewer.Interpolate

	viewer.announce(PAST, GENERATION, "A")
	viewer.announce(BARE, GENERATION, "A")

	for tick: number = FIRST, REVEAL - 1 do
		viewer.send({ tick = tick })
		Interpolate.frame(FRAME)
	end

	viewer.send({
		tick = REVEAL,
		reveals = {
			{ slot = PAST, generation = GENERATION, kind = "Player", past = past(PAST) },
			{ slot = BARE, generation = GENERATION, kind = "Player" },
			{ slot = HELD, generation = GENERATION, kind = "Player", past = past(HELD) },
		},
		records = { record(PAST, REVEAL), record(BARE, REVEAL), record(HELD, REVEAL) },
	})
	viewer.announce(HELD, GENERATION, "A")

	-- 1) On the first frame the render time lies inside the past, and the slot draws as a ring of its past and its
	-- block's own record does there
	Interpolate.frame(FRAME)
	local time: number = Interpolate.renderTime()
	if not (time >= REVEAL - AGES[1] and time < REVEAL) then
		return false, `The first frame after the reveal put the render time at {time}, outside the past it carries`
	end

	local samples: { any } = {}
	for _, age: number in AGES do
		table.insert(samples, { tick = REVEAL - age, record = record(PAST, REVEAL - age) })
	end
	table.insert(samples, { tick = REVEAL, record = record(PAST, REVEAL) })

	local drawn: boolean, state: any = viewer.pose(PAST)
	local ringed: boolean, expected: any = viewer.sample(samples)
	if not drawn or not ringed then
		return false, `On the first frame after its reveal the slot with a past drew {drawn} at render time {time}`
	elseif state.position ~= expected.position or state.velocity ~= expected.velocity then
		local found: string = `{state.position} moving {state.velocity}`
		return false, `The slot with a past was drawn at {found}, not {expected.position} moving {expected.velocity}`
	end

	-- 2) With no past, or the past a held reveal dropped, a slot draws only once the render time reaches its tick
	local reached: boolean = false
	for frame: number = 1, FRAMES do
		reached = Interpolate.renderTime() >= REVEAL

		for _, slot: number in { BARE, HELD } do
			local shown: boolean, now: any = viewer.pose(slot)
			if shown ~= reached then
				return false, `Frame {frame} after the reveal drew slot {slot} {shown} at {Interpolate.renderTime()}`
			elseif shown and now.position ~= at(slot, REVEAL) then
				return false, `Slot {slot} was first drawn at {now.position}, not its reveal's record`
			end
		end

		if reached then
			break
		end

		Interpolate.frame(FRAME)
	end

	if not reached then
		return false, `{FRAMES} frames after the reveal the render time was {Interpolate.renderTime()}, short of it`
	end

	-- 3) A change based on a past record's tick finds no baseline, so it drops and its block goes unacknowledged,
	-- while one based on the block's own record rebuilds
	local sequence: number = viewer.sequence
	local based: number = REVEAL - AGES[2]
	Interpolate.receive(Changes.block({
		sequence = sequence + 1,
		tick = NEXT,
		changes = {
			Changes.change(Changes.record(record(PAST, NEXT)), Changes.record(record(PAST, based)), NEXT - based),
		},
	}))

	local acknowledged: number = Interpolate.received()
	if acknowledged ~= sequence then
		return false, `A change based on a past record's tick was acknowledged as sequence {acknowledged}`
	end

	Interpolate.receive(Changes.block({
		sequence = sequence + 2,
		tick = AFTER,
		changes = {
			Changes.change(Changes.record(record(PAST, AFTER)), Changes.record(record(PAST, REVEAL)), AFTER - REVEAL),
		},
	}))

	acknowledged = Interpolate.received()
	if acknowledged ~= sequence + 2 then
		return false, `A change based on the reveal's own record left the acknowledgment at {acknowledged}`
	end

	return true, nil
end
