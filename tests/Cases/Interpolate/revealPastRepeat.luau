--[[
    A reveal with a past while its stretch is still open, its hide still
    waiting, adds only the past records newer than its ring's newest, and
    its repeat on the next block, its past a tick on, adds none of them
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 5
local GENERATION: number = 1
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local OPENED: number = 10 -- The reveal that opens the stretch, a record each tick after it
local HIDE: number = 15 -- Anti-ESP's hide, which waits while the render time is short of it
local AGAIN: number = 16 -- The reveal with its past while the stretch is open
local REPEAT: number = 17 -- The same reveal riding again
local FRAMES: number = 3 -- Frames drawn after the repeat
local AGES: { number } = { 3, 2, 1 }

-- Each record's height marks where it came from: the blocks' own, the reveal's past and the repeat's past
local SENT: number = 0
local PAST: number = 1
local REPEATED: number = 2

local function record(tick: number, height: number): { [string]: any }
	return { slot = SLOT, generation = GENERATION, position = vector.create(tick, height, 0) }
end

-- The reveal at a tick, its past marked at a height
local function reveal(tick: number, height: number): { [string]: any }
	local past: { any } = {}
	for _, age: number in AGES do
		table.insert(past, { age = age, record = record(tick - age, height) })
	end

	return { slot = SLOT, generation = GENERATION, kind = "Player", past = past }
end

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	viewer.announce(SLOT, GENERATION, "A")

	-- The ring each step should hold, oldest first
	local ring: { any } = {}

	-- Whether the slot draws as that ring does at the render time
	local function check(when: string): string?
		local drawn: boolean, state: any = viewer.pose(SLOT)
		local ringed: boolean, expected: any = viewer.sample(ring)
		if drawn ~= ringed then
			return `{when}, the slot drew {drawn} at render time {Interpolate.renderTime()}, where its ring draws {ringed}`
		elseif drawn and (state.position ~= expected.position or state.velocity ~= expected.velocity) then
			local found: string = `{state.position} moving {state.velocity}`
			return `{when}, the slot was drawn at {found}, not {expected.position} moving {expected.velocity}`
		end

		return nil
	end

	for tick: number = OPENED, HIDE - 1 do
		local reveals: { any }? = nil
		if tick == OPENED then
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } }
		end

		viewer.send({ tick = tick, reveals = reveals, records = { record(tick, SENT) } })
		table.insert(ring, { tick = tick, record = record(tick, SENT) })
		Interpolate.frame(FRAME)
	end

	viewer.send({ tick = HIDE, hides = { { slot = SLOT, generation = GENERATION, culled = true } } })
	Interpolate.frame(FRAME)
	if Interpolate.renderTime() >= HIDE or #viewer.hides ~= 0 then
		return false, `The hide closed the stretch by render time {Interpolate.renderTime()}, before the reveal came`
	end

	-- 1) Only the past newer than the ring's newest goes in, before the block's own record
	viewer.send({ tick = AGAIN, reveals = { reveal(AGAIN, PAST) }, records = { record(AGAIN, SENT) } })
	table.insert(ring, { tick = HIDE, record = record(HIDE, PAST) })
	table.insert(ring, { tick = AGAIN, record = record(AGAIN, SENT) })

	local why: string? = check("As the reveal arrived")
	if why then
		return false, why
	end

	Interpolate.frame(FRAME)
	why = check("A frame after the reveal")
	if why then
		return false, why
	end

	-- 2) The repeat's past is no newer than the ring's newest, so only its block's own record goes in
	viewer.send({ tick = REPEAT, reveals = { reveal(REPEAT, REPEATED) }, records = { record(REPEAT, SENT) } })
	table.insert(ring, { tick = REPEAT, record = record(REPEAT, SENT) })

	for frame: number = 0, FRAMES do
		if frame > 0 then
			Interpolate.frame(FRAME)
		end

		why = check(`{frame} frames after the repeat`)
		if why then
			return false, why
		end
	end

	if Interpolate.renderTime() < AGAIN then
		return false, `The frames ended at render time {Interpolate.renderTime()}, short of the reveal's past`
	elseif #viewer.reveals ~= 1 or #viewer.hides ~= 0 then
		return false, `The stretch was told {#viewer.reveals} reveals and {#viewer.hides} hides, not one reveal`
	end

	return true, nil
end
